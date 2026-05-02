@RestResource(urlMapping='/whatsapp')
global with sharing class WhatsAppWebhook {

    private static final Electra_Config__c CFG          = Electra_Config__c.getOrgDefaults();
    private static final String TWILIO_ACCOUNT_SID = CFG.Twilio_Account_SID__c;
    private static final String TWILIO_AUTH_TOKEN  = CFG.Twilio_Auth_Token__c;
    private static final String TWILIO_FROM_NUMBER = CFG.Twilio_From_Number__c;
    private static final String TWILIO_API_BASE    = 'https://api.twilio.com/2010-04-01/Accounts/';

    @HttpPost
    global static void handleIncoming() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;

        String message    = req.params.get('Body');
        String fromNumber = req.params.get('From');

        System.debug('WhatsAppWebhook.handleIncoming :: From=' + fromNumber + ' Body=' + message);

        String aiReply = getAIReply(message);
        aiReply = truncate(aiReply, 1500);
        System.debug('WhatsAppWebhook.handleIncoming :: AI reply=' + aiReply);

        sendTwilioMessage(fromNumber, aiReply);

        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf('{}');
    }

    // ── AI invocation ──────────────────────────────────────────────────────────

    private static String getAIReply(String message) {
        try {
            return AIAgentService.getReply(message);
        } catch (Exception ex) {
            System.debug('WhatsAppWebhook.getAIReply :: ERROR ' + ex.getMessage());
            return 'Tell me your budget and preference. I will suggest cars.';
        }
    }

    // ── Twilio callout ─────────────────────────────────────────────────────────

    private static void sendTwilioMessage(String toNumber, String body) {
        String endpoint = TWILIO_API_BASE + TWILIO_ACCOUNT_SID + '/Messages.json';

        String payload = buildFormPayload(
            new Map<String, String>{
                'From' => TWILIO_FROM_NUMBER,
                'To'   => toNumber,
                'Body' => body
            }
        );

        String credentials = TWILIO_ACCOUNT_SID + ':' + TWILIO_AUTH_TOKEN;
        String authHeader  = 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(credentials));

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod('POST');
        httpReq.setHeader('Authorization', authHeader);
        httpReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        httpReq.setBody(payload);

        System.debug('WhatsAppWebhook.sendTwilioMessage :: POST ' + endpoint);

        HttpResponse httpRes = new Http().send(httpReq);

        System.debug('WhatsAppWebhook.sendTwilioMessage :: Status=' + httpRes.getStatusCode()
                     + ' Body=' + httpRes.getBody());
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private static String buildFormPayload(Map<String, String> params) {
        List<String> parts = new List<String>();
        for (String key : params.keySet()) {
            parts.add(urlEncode(key) + '=' + urlEncode(params.get(key)));
        }
        return String.join(parts, '&');
    }

    private static String urlEncode(String value) {
        if (value == null) {
            return '';
        }
        return EncodingUtil.urlEncode(value, 'UTF-8');
    }

    private static String truncate(String text, Integer maxLen) {
        if (text == null) {
            return '';
        }
        if (text.length() <= maxLen) {
            return text;
        }
        return text.substring(0, maxLen - 3) + '...';
    }
}