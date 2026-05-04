public without sharing class TestDriveStatusEmailSender {

    public class Request {
        @InvocableVariable(label='Test Drive Id' required=true)
        public Id testDriveId;

        @InvocableVariable(
            label='Email Type'
            description='Either "Cancellation" or "Reschedule"'
            required=true
        )
        public String emailType;

        @InvocableVariable(label='Cancellation Reason')
        public String cancellationReason;
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
        label='Send Test Drive Status Email (Cancel/Reschedule)'
        description='Sends a status email (cancellation or reschedule) to the customer using details on the TestDrive and related Lead. Uses the org-wide email address so it works from agent context.'
        category='Test Drive'
    )
    public static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Resolve org-wide email address (so emails sent from the Einstein Agent User
        // — whose address is noreply@salesforce.com — are not silently dropped).
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
            // fall through
        }

        Set<Id> tdIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.testDriveId != null) {
                tdIds.add(r.testDriveId);
            }
        }

        Map<Id, TestDrive__c> tdMap = new Map<Id, TestDrive__c>();
        if (!tdIds.isEmpty()) {
            tdMap.putAll([
                SELECT Id, Name,
                       Test_Drive_Date__c, Previous_Test_Drive_Date__c,
                       Status__c, Cancellation_Reason__c,
                       Vehicle_Definition__c, Vehicle_Definition__r.Name,
                       Lead__c, Lead__r.Email, Lead__r.FirstName, Lead__r.LastName,
                       Lead__r.Phone, Lead__r.Customer_Zip_Code__c
                FROM TestDrive__c
                WHERE Id IN :tdIds
            ]);
        }

        List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>();
        List<Result> ordered = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();
            try {
                if (req.testDriveId == null || !tdMap.containsKey(req.testDriveId)) {
                    res.sent = false;
                    res.errorMessage = 'Test drive record not found.';
                    results.add(res);
                    continue;
                }

                TestDrive__c td = tdMap.get(req.testDriveId);
                res.bookingNumber = td.Name;

                String email = (td.Lead__r != null) ? td.Lead__r.Email : null;
                if (String.isBlank(email)) {
                    res.sent = false;
                    res.errorMessage = 'No email on the related Lead.';
                    results.add(res);
                    continue;
                }

                String firstName = (td.Lead__r != null) ? td.Lead__r.FirstName : null;
                String lastName  = (td.Lead__r != null) ? td.Lead__r.LastName : null;
                String displayName = String.isBlank(firstName) && String.isBlank(lastName)
                    ? 'Customer'
                    : ((firstName == null ? '' : firstName) + ' ' + (lastName == null ? '' : lastName)).trim();

                String phone = (td.Lead__r != null) ? td.Lead__r.Phone : '';
                String zip   = (td.Lead__r != null) ? td.Lead__r.Customer_Zip_Code__c : '';
                String vehicleName = (td.Vehicle_Definition__r != null) ? td.Vehicle_Definition__r.Name : '';

                String currentDateStr = td.Test_Drive_Date__c == null
                    ? '(unscheduled)'
                    : td.Test_Drive_Date__c.format('EEEE, MMMM d yyyy, h:mm a');
                String previousDateStr = td.Previous_Test_Drive_Date__c == null
                    ? ''
                    : td.Previous_Test_Drive_Date__c.format('EEEE, MMMM d yyyy, h:mm a');

                Boolean isCancel = String.isNotBlank(req.emailType)
                    && req.emailType.equalsIgnoreCase('Cancellation');

                String subject;
                String headline;
                String intro;
                String detailsRow = '';
                String waText;

                if (isCancel) {
                    subject  = 'Electra Cars — Test Drive Cancelled (' + td.Name + ')';
                    headline = 'Your Test Drive has been Cancelled';
                    intro    = 'We have cancelled your test drive booking. Details below for your records.';
                    String reason = String.isNotBlank(req.cancellationReason)
                        ? req.cancellationReason
                        : (String.isNotBlank(td.Cancellation_Reason__c) ? td.Cancellation_Reason__c : '');
                    if (String.isNotBlank(reason)) {
                        detailsRow = '<tr><td style="background:#f5f7fb;"><b>Cancellation Reason</b></td><td>' + reason + '</td></tr>';
                    }
                    waText = 'join%20clock-tall';
                } else {
                    subject  = 'Electra Cars — Test Drive Rescheduled (' + td.Name + ')';
                    headline = 'Your Test Drive has been Rescheduled';
                    intro    = 'Your test drive has been rescheduled. Updated details are below.';
                    if (String.isNotBlank(previousDateStr)) {
                        detailsRow = '<tr><td style="background:#f5f7fb;"><b>Previous Date &amp; Time</b></td><td>' + previousDateStr + '</td></tr>';
                    }
                    waText = 'join%20clock-tall';
                }

                String html =
                    '<div style="font-family:Arial,Helvetica,sans-serif;color:#222;">' +
                    '<h2 style="color:#0a4cb3;margin:0 0 12px 0;">' + headline + '</h2>' +
                    '<p>Hi ' + displayName + ',</p>' +
                    '<p>' + intro + '</p>' +
                    '<table cellpadding="8" style="border-collapse:collapse;border:1px solid #ddd;">' +
                    '<tr><td style="background:#f5f7fb;"><b>Booking Id</b></td><td>' + td.Name + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Name</b></td><td>' + displayName + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Email</b></td><td>' + email + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Phone</b></td><td>' + (phone == null ? '' : phone) + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>' + (isCancel ? 'Cancelled From' : 'New Date &amp; Time') + '</b></td><td>' + currentDateStr + '</td></tr>' +
                    detailsRow +
                    '<tr><td style="background:#f5f7fb;"><b>ZIP Code</b></td><td>' + (zip == null ? '' : zip) + '</td></tr>' +
                    '<tr><td style="background:#f5f7fb;"><b>Vehicle Model</b></td><td>' + vehicleName + '</td></tr>' +
                    '</table>' +
                    '<p style="margin-top:18px;">Need help or want to ' +
                    (isCancel ? 'book again' : 'change again') + '? ' +
                    'Message us on <a href="https://wa.me/+14155238886?text=' + waText + '" style="color:#25D366;font-weight:bold;text-decoration:none;">WhatsApp</a> ' +
                    'with your booking id <b>' + td.Name + '</b>.</p>' +
                    '<p style="margin-top:8px;font-size:13px;color:#555;">' +
                    'New to our WhatsApp assistant? ' +
                    '<a href="https://wa.me/+14155238886?text=' + waText + '" style="color:#0a4cb3;">Tap here to start chatting</a>.' +
                    '</p>' +
                    '<p>— Electra Cars Team</p>' +
                    '</div>';

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ email });
                mail.setSubject(subject);
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
