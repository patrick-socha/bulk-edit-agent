public with sharing class AddConfiguratorNodes {

    private static final String ENDPOINT_PATH = '/connect/cpq/configurator/actions/add-nodes';

    @InvocableMethod(
        label='Add Configurator Nodes'
        description='Add line items or bundle components to a product configuration session'
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
            body.put('contextId', req.contextId);
            body.put('addedNodes', JSON.deserializeUntyped(req.addedNodesJson));
            if (String.isNotBlank(req.configuratorOptionsJson)) {
                body.put('configuratorOptions', JSON.deserializeUntyped(req.configuratorOptionsJson));
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
            label='Context ID'
            description='Session handle returned by LoadConfiguratorSession'
            required=true
        )
        public String contextId;

        @InvocableVariable(
            label='Added Nodes JSON'
            description='JSON array of Configurator Added Node Input objects (path + addedObject)'
            required=true
        )
        public String addedNodesJson;

        @InvocableVariable(
            label='Configurator Options JSON'
            description='Optional JSON string of Configurator Options Input'
            required=false
        )
        public String configuratorOptionsJson;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if all nodes were added successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API'
        )
        public String responseBody;
    }
}
