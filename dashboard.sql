-- Сколько у нас пользователей заходят на сайт (уникальных - distinct) в день
select
    date_trunc('day', visit_date) as visit_date,
    count(/*distinct*/ visitor_id)
from sessions
group by 1
order by 1;

-- Какие каналы их приводят на сайт? Хочется видеть по дням/неделям/месяцам
-- по дням
select
    source,
    count(*),
    date_trunc('day', visit_date) as visit_date
from sessions
group by 1, 3
order by visit_date;

-- по неделям
select
    source,
    count(*),
    date_trunc('week', visit_date) as visit_date
from sessions
group by 1, 3
order by visit_date;

-- по месяцам
select
    source,
    count(*),
    date_trunc('month', visit_date) as visit_date
from sessions
group by 1, 3
order by visit_date;

-- Сколько лидов к нам приходят?
select
    date_trunc('day', created_at),
    count(*)
from leads
group by 1
order by 1;

-- Какая конверсия из клика в лид? А из лида в оплату?
-- Далее используем витрину aggregate_last_paid_click
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
count_buy AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        date(visit_date) AS visit_date,
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
        sum(amount) AS revenue
    FROM last_paid_click
    WHERE last_paid_click.rn = 1
    GROUP BY
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
),

advertising AS (
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY 1, 2, 3, 4
    UNION ALL
    SELECT
        campaign_date AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY 1, 2, 3, 4
)

SELECT
    cb.utm_source,
    cb.utm_medium,
    cb.utm_campaign,
    date(cb.visit_date) AS visit_date,
    sum(visitors_count) AS visitors_count,
    sum(total_cost) AS total_cost,
    sum(leads_count) AS leads_count,
    sum(purchases_count) AS purchases_count,
    sum(revenue) AS revenue
FROM advertising AS a
RIGHT JOIN count_buy AS cb
    ON
        a.visit_date = cb.visit_date
        AND a.utm_source = cb.utm_source
        AND a.utm_medium = cb.utm_medium
        AND a.utm_campaign = cb.utm_campaign
GROUP BY
    cb.visit_date,
    cb.utm_source,
    cb.utm_medium,
    cb.utm_campaign
ORDER BY
    revenue DESC NULLS LAST,
    visit_date ASC,
    visitors_count DESC,
    utm_source ASC,
    utm_medium ASC,
    utm_campaign ASC
)

SELECT
    utm_source,
    round(
        sum(leads_count) * 100.00 / sum(visitors_count), 2
    ) AS visitor_from_lead,
    CASE
        WHEN sum(coalesce(leads_count, 0)) = 0 THEN 0.00 ELSE
            round(
                sum(coalesce(purchases_count, 0))
                * 100.00
                / sum(coalesce(leads_count, 0)),
                2
            )
    END AS lead_from_paid
FROM big_tab
GROUP BY 1
HAVING round(sum(leads_count) * 100.00 / sum(visitors_count), 2) != 0
ORDER BY lead_from_paid DESC;

-- Сколько мы тратим по разным каналам в динамике?
/*aggregate_last_paid_click*/
select
    case
        when extract(day from visit_date) between 1 and 7 then 1
        when extract(day from visit_date) between 8 and 14 then 2
        when extract(day from visit_date) between 15 and 21 then 3
        else 4
    end as weekpart,
    sum(total_cost),
    utm_source
from big_tab
group by 1, 3
having sum(total_cost) > 0;

-- Окупаются ли каналы?
/*aggregate_last_paid_click*/
select
    utm_source,
    sum(coalesce(total_cost, 0)) as total_cost,
    sum(coalesce(revenue, 0)) as total_revenue,
    sum(coalesce(revenue, 0)) - sum(coalesce(total_cost, 0)) as payback
from big_tab
group by 1
having sum(total_cost) > 0 or sum(revenue) > 0;

-- Сколько кликов на рекламу совершается и траты на рекламу по utm_campaign 
with tab as (
    select
        source as utm_source,
        campaign as utm_campaign,
        count(*) as count_click,
        null as daily_spent
    from sessions
    group by 1, 2
),

tab2 as (
    select
        utm_source,
        utm_campaign,
        sum(daily_spent) as daily_spent,
        null as count_click
    from ya_ads
    group by 1, 2
    union
    select
        utm_source,
        utm_campaign,
        sum(daily_spent) as daily_spent,
        null as count_click
    from vk_ads
    group by 1, 2
    order by 1
)

select
    tab2.utm_source,
    tab2.utm_campaign,
    tab2.daily_spent,
    tab.count_click
from tab
inner join tab2
    on tab.utm_campaign = tab2.utm_campaign and tab.utm_source = tab2.utm_source
order by 1, 3 desc;

-- Таблица с расчетами cpu/cpl/cppu/roi по utm_source
-- /*aggregate_last_paid_click*/
select
    utm_source,
    round(sum(coalesce(total_cost, 0)) / sum(visitors_count), 2) as cpu,
    round(sum(coalesce(total_cost, 0)) / sum(leads_count), 2) as cpl,
    round(sum(coalesce(total_cost, 0)) / sum(purchases_count), 2) as cppu,
    round(
        (sum(coalesce(revenue, 0)) - sum(coalesce(total_cost, 0)))
        * 100.00
        / sum(coalesce(total_cost, 0)),
        2
    ) as roi
from big_tab
group by 1
having sum(total_cost) > 0;

-- Расчет среднего, минимального и максимального чека по формату обучения и дате
select
    to_char(created_at, 'YYYY-MM-DD'),
    learning_format,
    avg(amount) as avg_amount,
    min(amount) as min_amount,
    max(amount) as max_amount
from leads
where status_id = 142
group by 1, learning_format
order by 2, 1;
    
-- Через какое время после запуска компании маркетинг может анализировать компанию используя ваш дашборд?
-- Можно посчитать за сколько дней с момента перехода по рекламе закрывается 90% лидов.
with tab as (
    select
        s.visitor_id,
        s.visit_date as visit_date,
        s.source as utm_source,
        l.lead_id,
        l.created_at as created_at,
        row_number() over (partition by s.visitor_id order by s.visit_date desc)
        as rn
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date <= l.created_at
    where s.source in ('yandex', 'vk', 'telegram')
)

select
    utm_source,
    case
        when utm_source = 'yandex'
            then
                percentile_disc(0.9) within group (
                    order by created_at - visit_date
                )
        when utm_source = 'vk'
            then
                percentile_disc(0.9) within group (
                    order by created_at - visit_date
                )
        when utm_source = 'telegram'
            then
                percentile_disc(0.9) within group (
                    order by created_at - visit_date
                )
    end as percent_90_leads
from tab
where rn = 1
group by 1;
