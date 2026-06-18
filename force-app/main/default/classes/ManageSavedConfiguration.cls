public with sharing class ManageSavedConfiguration {

    private static final String BASE_PATH = '/connect/cpq/configurator/saved-configuration';

    @InvocableMethod(
        label='Manage Saved Configuration'
        description='List, save, update, or delete a saved configuration template. Set operation to LIST, SAVE, UPDATE, or DELETE.'
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
            String op = req.operation != null ? req.operation.toUpperCase() : '';

            if (op == 'LIST') {
                r = doList(req);
            } else if (op == 'SAVE') {
                r = doSave(req);
            } else if (op == 'UPDATE') {
                r = doUpdate(req);
            } else if (op == 'DELETE') {
                r = doDelete(req);
            } else {
                r.isSuccess = false;
                r.errorMessage = 'Invalid operation: ' + req.operation + '. Must be LIST, SAVE, UPDATE, or DELETE.';
            }
        } catch (Exception e) {
            r.isSuccess = false;
            r.errorMessage = e.getMessage();
        }
        return r;
    }

    private static Result doList(Request req) {
        Result r = new Result();
        String endpoint = 'callout:Configurator_API/services/data/v67.0' + BASE_PATH
            + '?referenceRecordId=' + EncodingUtil.urlEncode(req.referenceRecordId, 'UTF-8');

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setMethod('GET');

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
        return r;
    }

    private static Result doSave(Request req) {
        Result r = new Result();
        Map<String, Object> body = new Map<String, Object>();
        body.put('referenceRecordId', req.referenceRecordId);
        if (String.isNotBlank(req.savedConfigName)) {
            body.put('name', req.savedConfigName);
        }
        if (String.isNotBlank(req.savedConfigDescription)) {
            body.put('description', req.savedConfigDescription);
        }
        if (String.isNotBlank(req.dataJson)) {
            body.put('data', req.dataJson);
        }

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('callout:Configurator_API/services/data/v67.0' + BASE_PATH);
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setMethod('POST');
        httpReq.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse resp = http.send(httpReq);

        r.responseBody = resp.getBody();
        if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            // The SAVE endpoint can return HTTP 200 with a body-level error (e.g.
            // "MISSING FAVORITE DATA") and an empty id. Treat a non-empty errors array
            // OR a blank id as failure — do not report false success on 2xx alone.
            Object errs = parsed.get('errors');
            Boolean hasErrors = errs instanceof List<Object> && !((List<Object>) errs).isEmpty();
            String newId = (String) parsed.get('id');
            if (hasErrors || String.isBlank(newId)) {
                r.isSuccess = false;
                r.errorMessage = errs != null ? JSON.serialize(errs) : 'Save did not return an id';
            } else {
                r.isSuccess = true;
                r.savedConfigId = newId;
            }
        } else {
            r.isSuccess = false;
            r.errorMessage = 'HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
        }
        return r;
    }

    private static Result doUpdate(Request req) {
        Result r = new Result();
        Map<String, Object> body = new Map<String, Object>();
        body.put('name', req.savedConfigName);
        body.put('description', req.savedConfigDescription != null ? req.savedConfigDescription : '');
        body.put('data', req.dataJson != null ? req.dataJson : '');

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('callout:Configurator_API/services/data/v67.0' + BASE_PATH + '/' + req.savedConfigId);
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setMethod('PUT');
        httpReq.setBody(JSON.serialize(body));

        Http http = new Http();
        HttpResponse resp = http.send(httpReq);

        r.responseBody = resp.getBody();
        if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
            r.isSuccess = true;
            r.savedConfigId = req.savedConfigId;
        } else {
            r.isSuccess = false;
            r.errorMessage = 'HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
        }
        return r;
    }

    private static Result doDelete(Request req) {
        Result r = new Result();

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint('callout:Configurator_API/services/data/v67.0' + BASE_PATH + '/' + req.savedConfigId);
        httpReq.setMethod('DELETE');

        Http http = new Http();
        HttpResponse resp = http.send(httpReq);

        r.responseBody = resp.getBody();
        if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
            r.isSuccess = true;
        } else {
            r.isSuccess = false;
            r.errorMessage = 'HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
        }
        return r;
    }

    public class Request {
        @InvocableVariable(
            label='Operation'
            description='LIST, SAVE, UPDATE, or DELETE'
            required=true
        )
        public String operation;

        @InvocableVariable(
            label='Reference Record ID'
            description='Required for LIST and SAVE: the record (e.g. Quote ID) the saved configuration is associated with'
            required=false
        )
        public String referenceRecordId;

        @InvocableVariable(
            label='Saved Config ID'
            description='Required for UPDATE and DELETE: the ID of the saved configuration record'
            required=false
        )
        public String savedConfigId;

        @InvocableVariable(
            label='Name'
            description='Name for the saved configuration template (SAVE and UPDATE)'
            required=false
        )
        public String savedConfigName;

        @InvocableVariable(
            label='Config Description'
            description='Description of the saved configuration template (SAVE and UPDATE)'
            required=false
        )
        public String savedConfigDescription;

        @InvocableVariable(
            label='Data JSON'
            description='Stringified JSON of the configuration data to save (SAVE and UPDATE)'
            required=false
        )
        public String dataJson;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the operation completed successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Saved Config ID'
            description='ID of the saved configuration record (returned by SAVE; echoed on UPDATE)'
        )
        public String savedConfigId;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API'
        )
        public String responseBody;
    }
}
