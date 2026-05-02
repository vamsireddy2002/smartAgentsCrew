public with sharing class AIAgentService {

    // -- Configuration (values set via Setup > Custom Settings > Electra Config) -
    private static final Electra_Config__c CFG = Electra_Config__c.getOrgDefaults();
    private static final String ORG_DOMAIN    = CFG.SF_Org_Domain__c;
    private static final String ACTION_URL    = ORG_DOMAIN + '/services/data/v62.0/actions/custom/generateAiAgentResponse/Electra_Test_Drive_Assistant';
    private static final String TOKEN_URL     = ORG_DOMAIN + '/services/oauth2/token';
    private static final String CLIENT_ID     = CFG.SF_Client_ID__c;
    private static final String CLIENT_SECRET = CFG.SF_Client_Secret__c;

    // -- Public API -------------------------------------------------------------

    public static String getReply(String userMessage) {
        System.debug('AIAgentService.getReply :: userMessage=' + userMessage);
        try {
            String accessToken = getAccessToken();
            String reply       = invokeAgent(userMessage, accessToken);
            System.debug('AIAgentService.getReply :: reply=' + reply);
            return reply;
        } catch (Exception ex) {
            System.debug('AIAgentService.getReply :: ERROR ' + ex.getMessage());
            return 'ERROR: ' + ex.getMessage();
        }
    }

    // -- OAuth 2.0 Client Credentials ------------------------------------------

    private static String getAccessToken() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'grant_type=client_credentials' +
            '&client_id='     + EncodingUtil.urlEncode(CLIENT_ID,     'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(CLIENT_SECRET, 'UTF-8')
        );

        HttpResponse res = new Http().send(req);
        System.debug('AIAgentService.getAccessToken :: status=' + res.getStatusCode()
                     + ' body=' + res.getBody());

        if (res.getStatusCode() != 200) {
            throw new AIAgentException('Token error: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('access_token');
    }

    // -- Invoke Agent via Actions API -------------------------------------------

    private static String invokeAgent(String userMessage, String accessToken) {
        Map<String, Object> input = new Map<String, Object>{
            'userMessage' => userMessage
        };
        Map<String, Object> payload = new Map<String, Object>{
            'inputs' => new List<Object>{ input }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ACTION_URL);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);
        System.debug('AIAgentService.invokeAgent :: status=' + res.getStatusCode()
                     + ' body=' + res.getBody());

        if (res.getStatusCode() != 200) {
            throw new AIAgentException('Agent error: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        return extractReply(res.getBody());
    }

    // -- Parse Agent Reply ------------------------------------------------------

    private static String extractReply(String responseBody) {
        try {
            List<Object> results = (List<Object>) JSON.deserializeUntyped(responseBody);
            if (results != null && !results.isEmpty()) {
                Map<String, Object> first = (Map<String, Object>) results[0];
                Map<String, Object> outputValues = (Map<String, Object>) first.get('outputValues');
                if (outputValues != null) {
                    String agentResponse = (String) outputValues.get('agentResponse');
                    if (String.isNotBlank(agentResponse)) {
                        // agentResponse may be a JSON string like {"type":"Text","value":"..."}
                        try {
                            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(agentResponse);
                            String val = (String) parsed.get('value');
                            if (String.isNotBlank(val)) return val.trim();
                        } catch (Exception ex) {
                            // plain string — return as-is
                        }
                        return agentResponse.trim();
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('AIAgentService.extractReply :: parse error ' + ex.getMessage());
        }
        return fallback();
    }

    // -- Fallback ---------------------------------------------------------------

    private static String fallback() {
        return 'Somthing went wrong.Please try again later.';
    }

    public class AIAgentException extends Exception {}
}