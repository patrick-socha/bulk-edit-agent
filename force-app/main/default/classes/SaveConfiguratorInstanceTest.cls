@isTest
private class SaveConfiguratorInstanceTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_CONTEXT","message":"Context expired"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        SaveConfiguratorInstance.Request req = new SaveConfiguratorInstance.Request();
        req.contextId = 'ctx_001';
        List<SaveConfiguratorInstance.Result> results =
            SaveConfiguratorInstance.execute(new List<SaveConfiguratorInstance.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        SaveConfiguratorInstance.Request req = new SaveConfiguratorInstance.Request();
        req.contextId = 'bad-ctx';
        List<SaveConfiguratorInstance.Result> results =
            SaveConfiguratorInstance.execute(new List<SaveConfiguratorInstance.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
