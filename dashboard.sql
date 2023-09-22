-- Сколько у нас пользователей заходят на сайт (уникальных - distinct) в день
select date_trunc('day', visit_date) visit_date, count(/*distinct*/ visitor_id) from sessions
group by 1
order by 1

-- Какие каналы их приводят на сайт? Хочется видеть по дням/неделям/месяцам
select medium, count(*), date_trunc('day', visit_date) visit_date from sessions s -- по дням
group by 1, 3
order by visit_date

select medium, count(*), date_trunc('week', visit_date) visit_date from sessions s -- по неделям
group by 1, 3
order by visit_date

select medium, count(*), date_trunc('month', visit_date) visit_date from sessions s  -- по месяцам
group by 1, 3
order by visit_date

-- Сколько лидов к нам приходят?
select date_trunc('day', created_at), count(1) from leads l
group by 1
order by 1

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
), big_tab as 
(
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
    utm_campaign asc
    ) 
    select
    utm_source,
    round(sum(leads_count) * 100.00 / sum(visitors_count), 2) as visitor_from_lead,
    case
        when sum(coalesce(leads_count, 0)) = 0 then 0.00 else
            round(sum(coalesce(purchases_count, 0))* 100.00 / sum(coalesce(leads_count, 0)), 2)
    end as lead_from_paid
from big_tab
group by 1;

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
having sum(total_cost)>0 or sum(revenue)>0;

-- Таблица с расчетами cpu/cpl/cppu/roi по utm_source
-- /*aggregate_last_paid_click*/
select
    utm_source,
    round(sum(coalesce(total_cost, 0)) / sum(visitors_count), 2) as cpu,
    round(sum(coalesce(total_cost, 0)) / sum(leads_count), 2) as cpl,
    round(sum(coalesce(total_cost, 0)) / sum(purchases_count), 2) as cppu,
    round((sum(coalesce(revenue, 0)) - sum(coalesce(total_cost, 0))) * 100.00 / sum(coalesce(total_cost, 0)), 2) as roi
from big_tab
group by 1
having sum(total_cost)>0;

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
    from sessions s
    left join leads l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date <= l.created_at
    where s.source in ('yandex', 'vk', 'telegram')
)
select
    utm_source,
    case
        when utm_source = 'yandex'
        then percentile_disc(0.9) within group (order by created_at - visit_date)
        when utm_source = 'vk'
        then percentile_disc(0.9) within group (order by created_at - visit_date)
        when utm_source = 'telegram'
        then percentile_disc(0.9) within group (order by created_at - visit_date)        
    end as percent_90_leads
from tab
where rn = 1
group by 1;
