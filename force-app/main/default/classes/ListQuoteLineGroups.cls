/**
 * Lists the GROUP/SUBGROUP hierarchy on a quote (e.g. regions like "GEO #2 - CALIFORNIA"
 * and their subgroups "LOS ANGELES" / "SAN FRANCISCO"), with the number of line items in
 * each group. The agent uses this to:
 *   - ground a casual region name ("California") to the canonical group Name,
 *   - show the rep how many bundles a region holds (incl. via subgroups),
 *   - compute an "all except X" complement before a scoped bulk change.
 *
 * Read-only discovery. Group scoping itself is resolved/applied by QuoteLineGroupScope and
 * the bulk classes.
 */
public with sharing class ListQuoteLineGroups {

    @InvocableMethod(
        label='List Quote Line Groups'
        description='List the group/region hierarchy on a quote (groups and their subgroups) with a per-group line-item count. Use to ground a casual region name to the real group, show bundle counts, and confirm scope before a scoped bulk change.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Collect quote IDs across all requests (bulk-safe).
        Set<Id> quoteIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.quoteId)) {
                try { quoteIds.add((Id) req.quoteId); } catch (Exception e) {}
            }
        }

        // Groups per quote.
        Map<Id, List<QuoteLineGroup>> groupsByQuote = new Map<Id, List<QuoteLineGroup>>();
        Map<Id, String> nameById = new Map<Id, String>();
        if (!quoteIds.isEmpty()) {
            for (QuoteLineGroup g : [
                SELECT Id, Name, QuoteId, ParentQuoteLineGroupId, SortOrder
                FROM QuoteLineGroup
                WHERE QuoteId IN :quoteIds
                WITH USER_MODE
                ORDER BY SortOrder, Name
            ]) {
                if (!groupsByQuote.containsKey(g.QuoteId)) {
                    groupsByQuote.put(g.QuoteId, new List<QuoteLineGroup>());
                }
                groupsByQuote.get(g.QuoteId).add(g);
                nameById.put(g.Id, g.Name);
            }
        }

        // Line-item count per group (aggregate; read-only).
        Map<Id, Integer> countByGroup = new Map<Id, Integer>();
        if (!quoteIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT QuoteLineGroupId gid, COUNT(Id) total
                FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds AND QuoteLineGroupId != null
                WITH USER_MODE
                GROUP BY QuoteLineGroupId
            ]) {
                countByGroup.put((Id) ar.get('gid'), (Integer) ar.get('total'));
            }
        }

        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.quoteId)) {
                    r.isSuccess = false;
                    r.errorMessage = 'quoteId is required.';
                    results.add(r);
                    continue;
                }
                List<QuoteLineGroup> groups = groupsByQuote.get((Id) req.quoteId);
                List<Map<String, Object>> out = new List<Map<String, Object>>();
                if (groups != null) {
                    for (QuoteLineGroup g : groups) {
                        Integer c = countByGroup.containsKey(g.Id) ? countByGroup.get(g.Id) : 0;
                        out.add(new Map<String, Object>{
                            'groupId' => g.Id,
                            'name' => g.Name,
                            'parentName' => g.ParentQuoteLineGroupId != null
                                ? nameById.get(g.ParentQuoteLineGroupId) : null,
                            'isSubgroup' => g.ParentQuoteLineGroupId != null,
                            'bundleCount' => c
                        });
                    }
                }
                r.isSuccess = true;
                r.groupCount = out.size();
                r.groupsJson = JSON.serialize(out);
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
            description='The Quote whose group/region hierarchy to list'
            required=true
        )
        public String quoteId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the groups were retrieved'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Groups JSON'
            description='JSON array of groups; each has groupId, name, parentName, isSubgroup, bundleCount (line items directly in that group). A group with bundleCount 0 may still hold bundles in its subgroups.'
        )
        public String groupsJson;

        @InvocableVariable(
            label='Group Count'
            description='Number of groups (including subgroups) on the quote'
        )
        public Integer groupCount;
    }
}
