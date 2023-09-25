--витрина last_paid_click
WITH last_paid_click AS (
    SELECT
        s.visitor_id,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        lead_id,
        created_at,
        closing_reason,
        status_id,
        date(visit_date) AS visit_date,
        coalesce(amount, 0) AS amount,
        row_number()
            OVER (PARTITION BY s.visitor_id ORDER BY visit_date DESC)
        AS rn
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE s.medium NOT IN ('organic')
),

-- Траты на рекламу за 1 день
advertising AS (
    SELECT
        date(visit_date) AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(visitor_id) AS visitors_count,
        sum(CASE WHEN lead_id IS NOT null THEN 1 ELSE 0 END) AS leads_count,
        sum(
            CASE
                WHEN
                    closing_reason = 'Успешная продажа' OR status_id = 142
                    THEN 1
                ELSE 0
            END
        ) AS purchases_count,
        sum(amount) AS revenue,
        null AS total_cost
    FROM last_paid_click
    WHERE last_paid_click.rn = 1
    GROUP BY
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    UNION ALL
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        null AS revenue,
        null AS visitors_count,
        null AS leads_count,
        null AS purchases_count,
        daily_spent AS total_cost
    FROM vk_ads
    UNION ALL
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        null AS revenue,
        null AS visitors_count,
        null AS leads_count,
        null AS purchases_count,
        daily_spent AS total_cost
    FROM ya_ads
)

SELECT
    utm_source,
    utm_medium,
    utm_campaign,
    date(visit_date) AS visit_date,
    sum(visitors_count) AS visitors_count,
    sum(total_cost) AS total_cost,
    sum(leads_count) AS leads_count,
    sum(purchases_count) AS purchases_count,
    sum(revenue) AS revenue
FROM advertising
GROUP BY
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign
ORDER BY
    revenue DESC NULLS LAST,
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC;
