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
