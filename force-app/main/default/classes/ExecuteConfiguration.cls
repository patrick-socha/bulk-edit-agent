public with sharing class ExecuteConfiguration {

    private static final String ENDPOINT_PATH = '/connect/cpq/configurator/actions/configure';

    @InvocableMethod(
        label='Execute Configuration'
        description='Execute configuration rules, validate changes, and retrieve pricing for the transaction'
        callout=true
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(process(req));
        }
        return results;
    }

    private static Result process(Request req) {
        Result r = new Result();
        try {
            Map<String, Object> body = new Map<String, Object>();
            body.put('transactionId', req.transactionId);
            if (String.isNotBlank(req.addedNodesJson)) {
                body.put('addedNodes', JSON.deserializeUntyped(req.addedNodesJson));
            }
            if (String.isNotBlank(req.updatedNodesJson)) {
                body.put('updatedNodes', JSON.deserializeUntyped(req.updatedNodesJson));
            }
            if (String.isNotBlank(req.deletedNodesJson)) {
                body.put('deletedNodes', JSON.deserializeUntyped(req.deletedNodesJson));
            }
            if (String.isNotBlank(req.configuratorOptionsJson)) {
                body.put('configuratorOptions', JSON.deserializeUntyped(req.configuratorOptionsJson));
            }
            if (String.isNotBlank(req.contextResponseType)) {
                body.put('contextResponseType', req.contextResponseType);
            }

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('callout:Configurator_API/services/data/v67.0' + ENDPOINT_PATH);
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setMethod('POST');
            httpReq.setBody(JSON.serialize(body));

            Http http = new Http();
            HttpResponse resp = http.send(httpReq);

            r.responseBody = resp.getBody();
            if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                r.isSuccess = parsed.get('success') == true;
                Object msgs = parsed.get('messages');
                r.messagesJson = msgs != null ? JSON.serialize(msgs) : null;
                if (!r.isSuccess) {
                    Object errs = parsed.get('errors');
                    r.errorMessage = errs != null ? JSON.serialize(errs) : 'Unknown error from API';
                }
            } else {
                r.isSuccess = false;
                r.errorMessage = 'HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
            }
        } catch (Exception e) {
            r.isSuccess = false;
            r.errorMessage = e.getMessage();
        }
        return r;
    }

    public class Request {
        @InvocableVariable(
            label='Transaction ID'
            description='The quote or order ID for the transaction to configure'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Added Nodes JSON'
            description='Optional JSON array of Configurator Added Node Input objects'
            required=false
        )
        public String addedNodesJson;

        @InvocableVariable(
            label='Updated Nodes JSON'
            description='Optional JSON array of Configurator Updated Node Input objects'
            required=false
        )
        public String updatedNodesJson;

        @InvocableVariable(
            label='Deleted Nodes JSON'
            description='Optional JSON array of Configurator Deleted Node Input objects'
            required=false
        )
        public String deletedNodesJson;

        @InvocableVariable(
            label='Configurator Options JSON'
            description='Optional JSON string of Configurator Options Input'
            required=false
        )
        public String configuratorOptionsJson;

        @InvocableVariable(
            label='Context Response Type'
            description='Required for large transactions (>1000 line items): Delta, Full, None, or Product'
            required=false
        )
        public String contextResponseType;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the configuration executed without errors'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Messages JSON'
            description='Serialized JSON map of Configurator Messages (errors, warnings, info) from rule execution'
        )
        public String messagesJson;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API for downstream parsing'
        )
        public String responseBody;
    }
}
