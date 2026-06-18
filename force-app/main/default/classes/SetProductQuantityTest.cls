@isTest
private class SetProductQuantityTest {

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
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_QUANTITY","message":"Quantity must be positive"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        SetProductQuantity.Request req = new SetProductQuantity.Request();
        req.contextId = 'ctx_001';
        req.quantity = 5;
        req.transactionLinePathJson = '["Quote.QuoteLineItem.Quantity"]';
        List<SetProductQuantity.Result> results =
            SetProductQuantity.execute(new List<SetProductQuantity.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        SetProductQuantity.Request req = new SetProductQuantity.Request();
        req.contextId = 'bad-ctx';
        req.quantity = -1;
        req.transactionLinePathJson = '[]';
        List<SetProductQuantity.Result> results =
            SetProductQuantity.execute(new List<SetProductQuantity.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
