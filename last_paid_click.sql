WITH tab AS (
    SELECT
        s.visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        lead_id,
        created_at,
        amount,
        closing_reason,
        status_id,
        ROW_NUMBER() OVER (PARTITION BY lead_id ORDER BY visit_date DESC) AS rn
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE s.medium NOT IN ('organic')
)

SELECT
    visitor_id,
    date_trunc('day', visit_date) as visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    lead_id,
    created_at,
    amount,
    closing_reason,
    status_id
FROM tab
WHERE rn = 1
ORDER BY
    amount DESC NULLS LAST,
    visit_date ASC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC
LIMIT 10;
