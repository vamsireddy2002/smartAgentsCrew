/**
 * OTPGeneratorTest
 *
 * Unit test class for OTPGenerator.
 * Validates that the generated OTP:
 *   - Is always 6 digits
 *   - Falls within the expected range [100000, 999999]
 *   - Varies across multiple invocations (uniqueness check)
 *   - Handles bulk invocable requests correctly
 */
@IsTest
private class OTPGeneratorTest {

    /**
     * Happy path: single request returns a valid 6-digit OTP.
     */
    @IsTest
    static void testGenerate_returnsSixDigitOtp() {
        OTPGenerator.OTPRequest req = new OTPGenerator.OTPRequest();
        req.leadId = '00Q000000000001AAA';

        Test.startTest();
        List<OTPGenerator.OTPResult> results = OTPGenerator.generate(
            new List<OTPGenerator.OTPRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected exactly one result');

        String otp = results[0].otpCode;
        System.assertNotEquals(null, otp, 'OTP code must not be null');
        System.assertEquals(6, otp.length(), 'OTP must be exactly 6 characters');

        Integer otpInt = Integer.valueOf(otp);
        System.assert(
            otpInt >= 100000 && otpInt <= 999999,
            'OTP must be in range [100000, 999999]. Got: ' + otp
        );
    }

    /**
     * Bulk test: 10 requests all return valid, unique OTPs.
     * Collision probability is (10 * 9 / 2) / 900000 ≈ 0.005% — negligible.
     */
    @IsTest
    static void testGenerate_bulkRequestsReturnUniqueOtps() {
        List<OTPGenerator.OTPRequest> requests = new List<OTPGenerator.OTPRequest>();
        for (Integer i = 0; i < 10; i++) {
            OTPGenerator.OTPRequest req = new OTPGenerator.OTPRequest();
            req.leadId = '00Q00000000000' + String.valueOf(i).leftPad(4, '0') + 'AAA';
            requests.add(req);
        }

        Test.startTest();
        List<OTPGenerator.OTPResult> results = OTPGenerator.generate(requests);
        Test.stopTest();

        System.assertEquals(10, results.size(), 'Expected 10 results for 10 requests');

        Set<String> uniqueOtps = new Set<String>();
        for (OTPGenerator.OTPResult result : results) {
            System.assertNotEquals(null, result.otpCode, 'OTP must not be null');
            System.assertEquals(6, result.otpCode.length(), 'Each OTP must be 6 digits');

            Integer otpInt = Integer.valueOf(result.otpCode);
            System.assert(
                otpInt >= 100000 && otpInt <= 999999,
                'OTP out of range: ' + result.otpCode
            );

            uniqueOtps.add(result.otpCode);
        }

        System.assertEquals(
            10,
            uniqueOtps.size(),
            'All 10 OTPs should be unique (statistically near-certain)'
        );
    }

    /**
     * Validates the private generateSecureOtp method directly.
     * Runs 20 iterations to confirm range and format consistency.
     */
    @IsTest
    static void testGenerateSecureOtp_rangeAndFormat() {
        Test.startTest();
        for (Integer i = 0; i < 20; i++) {
            // Access via @TestVisible
            String otp = OTPGenerator.generateSecureOtp();
            System.assertEquals(6, otp.length(), 'OTP must always be 6 chars');
            System.assert(otp.isNumeric(), 'OTP must contain only digits');

            Integer otpInt = Integer.valueOf(otp);
            System.assert(
                otpInt >= 100000 && otpInt <= 999999,
                'OTP ' + otp + ' is outside the valid 6-digit range'
            );
        }
        Test.stopTest();
    }

    /**
     * Edge case: empty request list returns empty result list.
     * Guards against NullPointerException when the Flow passes no rows.
     */
    @IsTest
    static void testGenerate_emptyListReturnsEmptyResult() {
        Test.startTest();
        List<OTPGenerator.OTPResult> results = OTPGenerator.generate(
            new List<OTPGenerator.OTPRequest>()
        );
        Test.stopTest();

        System.assertNotEquals(null, results, 'Result list must not be null');
        System.assertEquals(0, results.size(), 'Result list must be empty for empty input');
    }
}
