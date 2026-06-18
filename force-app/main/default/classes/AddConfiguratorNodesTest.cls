@isTest
private class AddConfiguratorNodesTest {

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
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_NODE","message":"Bad node path"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        AddConfiguratorNodes.Request req = new AddConfiguratorNodes.Request();
        req.contextId = 'ctx_001';
        req.addedNodesJson = '[{"path":["0Q0000000000001","ref_001"],"addedObject":{"id":"ref_001","businessObjectType":"QuoteLineItem"}}]';
        List<AddConfiguratorNodes.Result> results =
            AddConfiguratorNodes.execute(new List<AddConfiguratorNodes.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        AddConfiguratorNodes.Request req = new AddConfiguratorNodes.Request();
        req.contextId = 'ctx_001';
        req.addedNodesJson = '[{}]';
        List<AddConfiguratorNodes.Result> results =
            AddConfiguratorNodes.execute(new List<AddConfiguratorNodes.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
