@isTest
private class QueryQuoteLineItemsTest {

    @isTest
    static void testBlankInputsFail() {
        QueryQuoteLineItems.Request req = new QueryQuoteLineItems.Request();
        req.quoteId = '';
        req.productId = '';
        List<QueryQuoteLineItems.Result> results =
            QueryQuoteLineItems.execute(new List<QueryQuoteLineItems.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @isTest
    static void testNoMatchReturnsEmpty() {
        // Valid-format but non-existent IDs: query returns nothing, success with 0 matches.
        QueryQuoteLineItems.Request req = new QueryQuoteLineItems.Request();
        req.quoteId = '0Q0000000000001AAA';
        req.productId = '01t000000000001AAA';
        List<QueryQuoteLineItems.Result> results =
            QueryQuoteLineItems.execute(new List<QueryQuoteLineItems.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(0, results[0].matchCount);
        System.assertEquals('', results[0].quoteLineItemIds);
    }
}
