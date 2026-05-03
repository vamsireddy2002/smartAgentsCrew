public without sharing class OTPEmailSender {

    public class SendRequest {
        @InvocableVariable(label='To Email Address' required=true)
        public String toEmail;

        @InvocableVariable(label='OTP Code' required=true)
        public String otpCode;

        @InvocableVariable(label='Customer Name' required=false)
        public String customerName;
    }

    public class SendResult {
        @InvocableVariable(label='Email Sent')
        public Boolean sent;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Send OTP Email'
        description='Sends a Salesforce platform email containing the OTP code to the given email address.'
        category='OTP Verification'
    )
    public static List<SendResult> sendOtpEmail(List<SendRequest> requests) {
        List<SendResult> results = new List<SendResult>();

        // Resolve an Org-Wide Email Address so that emails sent from contexts
        // where the running user's address is "noreply@salesforce.com"
        // (e.g. Agentforce / Einstein Agent User) are not silently dropped.
        Id oweId = null;
        try {
            List<OrgWideEmailAddress> owes = [
                SELECT Id, Address, DisplayName
                FROM OrgWideEmailAddress
                WHERE IsAllowAllProfiles = true
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!owes.isEmpty()) {
                oweId = owes[0].Id;
            }
        } catch (Exception ignore) {
            // Continue without OWE if query fails; fall back to running-user from address.
        }

        for (SendRequest req : requests) {
            SendResult result = new SendResult();
            try {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{ req.toEmail });
                if (oweId != null) {
                    mail.setOrgWideEmailAddressId(oweId);
                }
                mail.setSubject('Your Electra Cars Verification Code');
                String name = String.isBlank(req.customerName) ? 'Customer' : req.customerName;
                mail.setHtmlBody(
                    '<p>Hi ' + name + ',</p>' +
                    '<p>Your Electra Cars verification code is:</p>' +
                    '<p style="font-size:28px;font-weight:bold;letter-spacing:4px;">' + req.otpCode + '</p>' +
                    '<p>This code expires in <strong>5 minutes</strong>. Do not share it with anyone.</p>' +
                    '<p>— Electra Cars Team</p>'
                );
                Messaging.SendEmailResult[] emailResults = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ mail }
                );
                result.sent = emailResults[0].isSuccess();
                if (!result.sent) {
                    List<String> errs = new List<String>();
                    for (Messaging.SendEmailError e : emailResults[0].getErrors()) {
                        errs.add(e.getMessage());
                    }
                    result.errorMessage = String.join(errs, '; ');
                }
            } catch (Exception ex) {
                result.sent = false;
                result.errorMessage = ex.getMessage();
            }
            results.add(result);
        }

        return results;
    }
}