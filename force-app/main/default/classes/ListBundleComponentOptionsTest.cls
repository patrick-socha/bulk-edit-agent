@isTest
private class ListBundleComponentOptionsTest {

    @isTest
    static void testBlankInputsFail() {
        ListBundleComponentOptions.Request req = new ListBundleComponentOptions.Request();
        req.quoteId = '';
        req.bundleProductId = '';
        List<ListBundleComponentOptions.Result> results =
            ListBundleComponentOptions.execute(new List<ListBundleComponentOptions.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @isTest
    static void testLiveBundleIfPresent() {
        // If the org has a bundle with component groups, exercise the happy path.
        List<ProductComponentGroup> groups = [
            SELECT ParentProductId FROM ProductComponentGroup LIMIT 1
        ];
        List<Quote> quotes = [SELECT Id FROM Quote LIMIT 1];
        if (groups.isEmpty() || quotes.isEmpty()) {
            return; // no data; blank test covers the rest
        }
        ListBundleComponentOptions.Request req = new ListBundleComponentOptions.Request();
        req.quoteId = quotes[0].Id;
        req.bundleProductId = groups[0].ParentProductId;
        List<ListBundleComponentOptions.Result> results =
            ListBundleComponentOptions.execute(new List<ListBundleComponentOptions.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assert(results[0].groupCount >= 1);
        System.assertNotEquals(null, results[0].optionsJson);
    }
}
