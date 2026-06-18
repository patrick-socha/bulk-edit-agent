public with sharing class QueryQuoteLineItems {

    @InvocableMethod(
        label='Query Quote Line Items'
        description='Find QuoteLineItem IDs for a specific product on a quote. Returns matching QuoteLineItem IDs as a comma-separated list and as JSON.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // ── Collect all quote IDs and product IDs across requests ──
        Set<Id> quoteIds = new Set<Id>();
        Set<Id> productIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.quoteId)) {
                try { quoteIds.add((Id) req.quoteId); } catch (Exception e) {}
            }
            if (String.isNotBlank(req.productId)) {
                try { productIds.add((Id) req.productId); } catch (Exception e) {}
            }
        }

        // ── One bulk-safe query for all line items in scope ──
        List<QuoteLineItem> lineItems = new List<QuoteLineItem>();
        if (!quoteIds.isEmpty() && !productIds.isEmpty()) {
            lineItems = [
                SELECT Id, QuoteId, Product2Id
                FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds AND Product2Id IN :productIds
                WITH USER_MODE
            ];
        }

        // ── Map matches back to each request in memory (no SOQL in loop) ──
        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.quoteId) || String.isBlank(req.productId)) {
                    r.isSuccess = false;
                    r.errorMessage = 'Both quoteId and productId are required.';
                    results.add(r);
                    continue;
                }
                List<String> ids = new List<String>();
                for (QuoteLineItem qli : lineItems) {
                    if (qli.QuoteId == req.quoteId && qli.Product2Id == req.productId) {
                        ids.add(qli.Id);
                    }
                }
                r.isSuccess = true;
                r.matchCount = ids.size();
                r.quoteLineItemIds = String.join(ids, ',');
                r.recordsJson = JSON.serialize(ids);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Quote ID'
            description='The Quote ID to search within'
            required=true
        )
        public String quoteId;

        @InvocableVariable(
            label='Product ID'
            description='The Product2 ID to match on the quote'
            required=true
        )
        public String productId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the lookup completed successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Quote Line Item IDs'
            description='Comma-separated list of matching QuoteLineItem IDs'
        )
        public String quoteLineItemIds;

        @InvocableVariable(
            label='Records JSON'
            description='JSON array of matching QuoteLineItem IDs'
        )
        public String recordsJson;

        @InvocableVariable(
            label='Match Count'
            description='Number of matching QuoteLineItems found'
        )
        public Integer matchCount;
    }
}
