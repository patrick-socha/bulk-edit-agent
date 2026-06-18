@isTest
private class ExecuteConfigurationRulesTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"transactionContextId":"txnCtx_001"}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_TXN","message":"Transaction not found"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        ExecuteConfigurationRules.Request req = new ExecuteConfigurationRules.Request();
        req.transactionId = '0Q0000000000001';
        List<ExecuteConfigurationRules.Result> results =
            ExecuteConfigurationRules.execute(new List<ExecuteConfigurationRules.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        ExecuteConfigurationRules.Request req = new ExecuteConfigurationRules.Request();
        req.transactionId = 'bad-txn';
        List<ExecuteConfigurationRules.Result> results =
            ExecuteConfigurationRules.execute(new List<ExecuteConfigurationRules.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
