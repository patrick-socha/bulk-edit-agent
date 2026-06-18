@isTest
private class SelectBundleComponentTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else if (req.getEndpoint().contains('save-instance')) {
                resp.setBody('{"success":true,"errors":[]}');
            } else {
                // add-nodes / delete-nodes — clean success, no blocking messages
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{}}');
            }
            return resp;
        }
    }

    private class RuleBlockedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else {
                // delete-nodes returns a bundlevalidation warning -> must NOT save
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{"b":[{"messageType":"warning","category":"bundlevalidation","message":"Select child products in the range 1-1 and try again."}]}}');
            }
            return resp;
        }
    }

    @isTest
    static void testInvalidOperation() {
        SelectBundleComponent.Request req = new SelectBundleComponent.Request();
        req.operation = 'BOGUS';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleLineItemId = '0QL000000000001AAA';
        List<SelectBundleComponent.Result> res =
            SelectBundleComponent.execute(new List<SelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('SELECT or DESELECT'));
    }

    @isTest
    static void testMissingIds() {
        SelectBundleComponent.Request req = new SelectBundleComponent.Request();
        req.operation = 'SELECT';
        List<SelectBundleComponent.Result> res =
            SelectBundleComponent.execute(new List<SelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertNotEquals(null, res[0].errorMessage);
    }

    @isTest
    static void testDeselectNotOnQuote() {
        // DESELECT with a line item that isn't on the quote -> validation failure (no save).
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        SelectBundleComponent.Request req = new SelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleLineItemId = '0QL000000000001AAA';
        req.selectedLineItemId = '0QL000000000999AAA';
        List<SelectBundleComponent.Result> res =
            SelectBundleComponent.execute(new List<SelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
    }

    @isTest
    static void testSelectMissingPrc() {
        // SELECT without productRelatedComponentId -> caught as failure (no save).
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        SelectBundleComponent.Request req = new SelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleLineItemId = '0QL000000000001AAA';
        List<SelectBundleComponent.Result> res =
            SelectBundleComponent.execute(new List<SelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
    }
}
