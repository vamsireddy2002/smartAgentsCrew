public without sharing class BookingConfirmationEmailSender {

    public class Request {
        @InvocableVariable(label='Test Drive Id' required=true)
        public Id testDriveId;

        @InvocableVariable(label='Customer Email' required=true)
        public String customerEmail;

        @InvocableVariable(label='Customer Name' required=true)
        public String customerName;

        @InvocableVariable(label='Customer Phone')
        public String customerPhone;

        @InvocableVariable(label='Preferred Date & Time')
        public DateTime preferredDateTime;

        @InvocableVariable(label='ZIP Code')
        public String zipCode;

        @InvocableVariable(label='Vehicle Model')
        public String vehicleModel;
    }

    public class Result {
        @InvocableVariable(label='Email Sent')
        public Boolean sent;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Booking Number')
        public String bookingNumber;
    }

    @InvocableMethod(
        label='Send Test Drive Booking Confirmation Email'
        description='Sends a confirmation email to the customer with full booking details (Booking Id/Name, Name, Email, Phone, Preferred Date & Time, ZIP, Vehicle Model). Uses the org-wide email address so it works from agent context.'
        category='Test Drive'
    )
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Resolve an Org-Wide Email Address so emails sent from contexts where the
        // running user's address is "noreply@salesforce.com" (Einstein Agent User)
        // are not silently dropped.
        Id oweId = null;
        try {
            List<OrgWideEmailAddress> owes = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!owes.isEmpty()) {
                oweId = owes[0].Id;
            }
        } catch (Exception ignore) {
            // Fall through; running user's address will be used.
        }

        // Bulk-fetch TestDrive Names so we can include the human-readable booking number (TD-XXXXX).
        Set<Id> tdIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.testDriveId != null) {
                tdIds.add(r.testDriveId);
            }
        }
        Map<Id, TestDrive__c> tdMap = new Map<Id, TestDrive__c>();
        if (!tdIds.isEmpty()) {
            tdMap.putAll([SELECT Id, Name FROM TestDrive__c WHERE Id IN :tdIds]);
        }

        List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>();
        List<Result> ordered = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();
            try {
                String bookingName = (req.testDriveId != null && tdMap.containsKey(req.testDriveId))
                    ? tdMap.get(req.testDriveId).Name
                    : String.valueOf(req.testDriveId);
                res.bookingNumber = bookingName;

                String displayName = String.isBlank(req.customerName) ? 'Customer' : req.customerName;
                String whenStr = req.preferredDateTime == null
                    ? '(to be confirmed)'
                    : req.preferredDateTime.format('EEEE, MMMM d yyyy, h:mm a');

                String html =
                    '<div style="font-family:Arial,Helvetica,sans-serif;color:#222;">' +
                    '<h2 style="color:#0a4cb3;margin:0 0 12px 0;">Your Electra Cars Test Drive is Confirmed!</h2>' +
                    '<p>Hi ' + displayName + ',</p>' +
                    '<p>Thanks for booking a test drive with Electra Cars. Here are your booking details:</p>' +
                    '<table cellpadding="8" style="border-collapse:collapse;border:1px solid #ddd;">' +
                    '<tr><td style="background:#f5f7fb;"><b>Booking Id</b></td><td>' + bookingName + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Name</b></td><td>' + displayName + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Email</b></td><td>' + req.customerEmail + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Phone</b></td><td>' + (String.isBlank(req.customerPhone) ? '' : req.customerPhone) + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Preferred Date &amp; Time</b></td><td>' + whenStr + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>ZIP Code</b></td><td>' + (String.isBlank(req.zipCode) ? '' : req.zipCode) + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Vehicle Model</b></td><td>' + (String.isBlank(req.vehicleModel) ? '' : req.vehicleModel) + '</td></tr>' +
                    '</table>' +
                    '<p style="margin-top:18px;">Need to reschedule or cancel? Reply to this email or message us on WhatsApp with your booking id <b>' + bookingName + '</b>.</p>' +
                    '<p>— Electra Cars Team</p>' +
                    '</div>';

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ req.customerEmail });
                mail.setSubject('Electra Cars — Test Drive Confirmed (' + bookingName + ')');
                mail.setHtmlBody(html);
                if (oweId != null) {
                    mail.setOrgWideEmailAddressId(oweId);
                }

                toSend.add(mail);
                ordered.add(res);
            } catch (Exception ex) {
                res.sent = false;
                res.errorMessage = ex.getMessage();
                results.add(res);
            }
        }

        if (!toSend.isEmpty()) {
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(toSend, false);
            for (Integer i = 0; i < sendResults.size(); i++) {
                Result res = ordered[i];
                res.sent = sendResults[i].isSuccess();
                if (!res.sent) {
                    List<String> errs = new List<String>();
                    for (Messaging.SendEmailError e : sendResults[i].getErrors()) {
                        errs.add(e.getMessage());
                    }
                    res.errorMessage = String.join(errs, '; ');
                }
                results.add(res);
            }
        }

        return results;
    }
}
