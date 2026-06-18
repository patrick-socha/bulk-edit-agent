@isTest
private class SetConfiguratorInstanceTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"contextId":"ctx_002"}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_PAYLOAD","message":"Bad transaction JSON"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        SetConfiguratorInstance.Request req = new SetConfiguratorInstance.Request();
        req.contextMappingId = 'ctxMap_001';
        req.transactionJson = '{"id":"txn1"}';
        List<SetConfiguratorInstance.Result> results =
            SetConfiguratorInstance.execute(new List<SetConfiguratorInstance.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('ctx_002', results[0].contextId);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        SetConfiguratorInstance.Request req = new SetConfiguratorInstance.Request();
        req.contextMappingId = 'bad';
        req.transactionJson = 'invalid';
        List<SetConfiguratorInstance.Result> results =
            SetConfiguratorInstance.execute(new List<SetConfiguratorInstance.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
