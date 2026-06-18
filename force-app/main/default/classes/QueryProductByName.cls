public with sharing class QueryProductByName {

    @InvocableMethod(
        label='Query Product By Name'
        description='Find active Product2 records whose name matches the given text. Returns matching product IDs and names as JSON for use in configurator lookups.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // ── Collect distinct search terms across all requests ──
        Set<String> terms = new Set<String>();
        for (Request req : requests) {
            if (String.isNotBlank(req.productName)) {
                terms.add(req.productName.trim());
            }
        }

        // ── One bulk-safe query covering every term (OR of LIKEs) ──
        // Dynamic SOQL must use AccessLevel.USER_MODE, never the WITH USER_MODE clause.
        List<Product2> products = new List<Product2>();
        if (!terms.isEmpty()) {
            List<String> clauses = new List<String>();
            Map<String, Object> binds = new Map<String, Object>();
            Integer i = 0;
            for (String term : terms) {
                String key = 'term' + i;
                clauses.add('Name LIKE :' + key);
                binds.put(key, '%' + term + '%');
                i++;
            }
            String soql =
                'SELECT Id, Name, ProductCode FROM Product2 ' +
                'WHERE IsActive = true AND (' + String.join(clauses, ' OR ') + ') ' +
                'ORDER BY Name LIMIT 200';
            products = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        }

        // ── Map matches back to each request in memory (no SOQL in loop) ──
        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.productName)) {
                    r.isSuccess = false;
                    r.errorMessage = 'Product name is required.';
                    results.add(r);
                    continue;
                }
                String needle = req.productName.trim().toLowerCase();
                List<Map<String, Object>> matches = new List<Map<String, Object>>();
                for (Product2 p : products) {
                    if (p.Name != null && p.Name.toLowerCase().contains(needle)) {
                        matches.add(new Map<String, Object>{
                            'id' => p.Id,
                            'name' => p.Name,
                            'productCode' => p.ProductCode
                        });
                    }
                }
                r.isSuccess = true;
                r.matchCount = matches.size();
                r.recordsJson = JSON.serialize(matches);
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
            label='Product Name'
            description='Full or partial product name to search for'
            required=true
        )
        public String productName;
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
            label='Records JSON'
            description='JSON array of matching products, each with id, name, and productCode'
        )
        public String recordsJson;

        @InvocableVariable(
            label='Match Count'
            description='Number of matching products found'
        )
        public Integer matchCount;
    }
}
