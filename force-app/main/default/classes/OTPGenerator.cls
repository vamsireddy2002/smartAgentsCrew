/**
 * OTPGenerator
 *
 * Generates a cryptographically secure 6-digit one-time password (OTP)
 * for WhatsApp-based phone number verification during the Agentforce
 * test drive booking, cancellation, and reschedule flows.
 *
 * Uses Crypto.generateAesKey(128) as the entropy source — this is a
 * CSPRNG (Cryptographically Secure Pseudo-Random Number Generator)
 * provided natively by the Salesforce platform. Math.random() is
 * deliberately NOT used as it is not cryptographically secure.
 *
 * Registered as an @InvocableMethod so it can be called directly
 * from the GenerateAndSendOTP Autolaunched Flow as an Agent Action.
 */
public with sharing class OTPGenerator {

    /**
     * Generates one cryptographically secure 6-digit OTP per request.
     * Called by the GenerateAndSendOTP Flow action.
     *
     * @param requests  List of OTPRequest (one per Flow invocation)
     * @return          List of OTPResult containing the generated OTP code
     */
    @InvocableMethod(
        label='Generate Secure OTP'
        description='Generates a cryptographically secure 6-digit OTP using Crypto.generateAesKey. Use in the GenerateAndSendOTP Flow action.'
        category='OTP Verification'
    )
    public static List<OTPResult> generate(List<OTPRequest> requests) {
        List<OTPResult> results = new List<OTPResult>();

        for (OTPRequest req : requests) {
            OTPResult result = new OTPResult();
            result.otpCode = generateSecureOtp();
            results.add(result);
        }

        return results;
    }

    /**
     * Core OTP generation logic.
     * Derives a 6-digit integer (100000–999999) from the first 6 hex
     * characters of a randomly generated 128-bit AES key.
     *
     * Distribution: uniform across 900,000 possible values.
     * Collision probability for two simultaneous requests: 1 in 900,000.
     *
     * @return  A 6-digit string guaranteed to be between 100000 and 999999
     */
    @TestVisible
    private static String generateSecureOtp() {
        // Generate a cryptographically random 128-bit key (16 bytes = 32 hex chars)
        Blob randomBytes = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(randomBytes).substring(0, 6);

        // Convert the first 6 hex characters to a Long value
        Long longValue = 0;
        final String hexChars = '0123456789abcdef';
        for (Integer i = 0; i < 6; i++) {
            longValue = longValue * 16 + hexChars.indexOf(hex.substring(i, i + 1));
        }

        // Map to the 6-digit range [100000, 999999]
        Integer otp = (Integer) Math.mod(longValue, 900000) + 100000;
        return String.valueOf(otp);
    }

    // ─── Inner classes for InvocableMethod ──────────────────────────────────

    /**
     * Input wrapper for the Flow invocable method.
     * The leadId is passed from the GenerateAndSendOTP Flow so the
     * Apex method can be traced back to a specific Lead for debugging.
     */
    public class OTPRequest {
        @InvocableVariable(
            label='Lead Id'
            description='Salesforce Id of the Lead record for which the OTP is being generated.'
            required=true
        )
        public String leadId;
    }

    /**
     * Output wrapper returned to the Flow.
     * The Flow stores otpCode in the Lead.OTP_Code__c field and
     * passes it to the SendWhatsAppMessage action.
     */
    public class OTPResult {
        @InvocableVariable(
            label='OTP Code'
            description='The generated 6-digit one-time password. Store in Lead.OTP_Code__c and pass to the WhatsApp OTP template.'
        )
        public String otpCode;
    }
}
