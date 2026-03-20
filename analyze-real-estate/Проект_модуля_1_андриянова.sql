-- 1 задача Определим аномальные значения (выбросы) по значению перцентилей:
-- можно я не буду сейчас менять все названия  столбцов на англ, мне лень, но я поняла замечание, учту
----------------------------------------------------------------------------------------------------------------------------------------------------
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) 	AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats f
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
category as (
    select *, 
    case when c.city = 'Санкт-Петербург' then 'Санкт-Петербург'
    else 'ЛенОбл' 
    end as регион,
    case when days_exposition between 1 and 30 then 'до месяца'
        when days_exposition between 31 and 90 then 'до квартала'
        when days_exposition between 91 and 180 then 'до полугода'
        when days_exposition >= 181 then 'больше полугода'
        end as сегмент_активности
    from real_estate.advertisement as a
    left join real_estate.flats f using(id)			
    left join real_estate.city c using(city_id)
    inner join filtered_id ff on a.id = ff.id
    where days_exposition is not null
    and type_id='F8EM'								
    and a.last_price > 0
    and f.total_area > 0
),
region_totals as (
    select 
        регион,
        count(*) as total_ads
    from category
    group by регион
),
segment_counts as (
    select 
        регион,
        сегмент_активности,
        count(*) as ad_count,
        round(avg(last_price::numeric/total_area::numeric),0) as avg_price_per_m2,
        round(avg(total_area::numeric),2) as avg_area,
        percentile_disc(0.5) within group (order by rooms) as median_rooms,
        percentile_disc(0.5) within group (order by balcony) as median_balcony,
        percentile_disc(0.5) within group (order by floor) as median_floor,
        sum(case when rooms = 0 then 1 else 0 end) as studio_count,
        avg(ceiling_height) as ceil_high
    from category    
    group by регион, сегмент_активности
)
select 
    sc.регион,
    sc.сегмент_активности,
    sc.ad_count as количество_объявлений,
   -- COUNT(*) / SUM(COUNT(*)) OVER() AS share_total,
--COUNT(*) / SUM(COUNT(*)) OVER(PARTITION BY sc.регион) AS share_region , если это юзать, чуть переделать код надо и добавить группировку
    round((sc.ad_count::numeric / rt.total_ads * 100), 1) as доля_объявлений_в_регионе,
    sc.avg_price_per_m2 as средняя_цена_м2,
    sc.avg_area as средняя_площадь,
    sc.median_rooms as медиана_комнат,
    sc.median_balcony as медиана_балконов,
    sc.median_floor as медиана_этажности,
    round(studio_count::numeric * 100.0 / ad_count,2) as "доля_студий_%",
    round(ceil_high::numeric, 2) as ср_высота_потолка    
from segment_counts sc
left join region_totals rt on sc.регион = rt.регион
order by sc.регион desc,
    case sc.сегмент_активности
        when 'до месяца' then 1
        when 'до квартала' then 2
        when 'до полугода' then 3
        else 4
    end;














-- 2 задача  В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? А в какие — по снятию?
----------------------------------------------------------------------------------------------------------------------------------------------------

with limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) 	AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats f
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
publ as (
select extract(MONTH from first_day_exposition) AS month_number,
        TO_CHAR(first_day_exposition, 'Month') AS month_name,
count(*) as published_ads,
avg(count(*)) over() as avg_monthly_published,
avg(last_price/total_area) as avg_price_m2,
avg(total_area) as avg_m2,
rank() over(order by count(*) desc) as publication_rank
from real_estate.advertisement a
left join real_estate.flats f using(id)
inner join filtered_id ff on a.id = ff.id
where first_day_exposition is not null 
and type_id='F8EM'								
    and a.last_price > 0
    and f.total_area > 0
GROUP BY month_number, month_name
order by month_number
),
end_publ as(
select extract(month from (first_day_exposition + (days_exposition * INTERVAL '1 day'))) as month_number,
count(*) as removed_ads,
avg(count(*)) over() as avg_monthly_removed,
avg(last_price/total_area) as avg_price_m2,
avg(total_area) as avg_m2,
rank() over(order by count(*) desc) as removal_rank
from real_estate.advertisement a
left join real_estate.flats f using(id)
inner join filtered_id ff on a.id = ff.id
where first_day_exposition is not null
and days_exposition IS NOT NULL
and type_id='F8EM'								
    and a.last_price > 0
    and f.total_area > 0
GROUP BY month_number
order by month_number
)
select 
p.month_number as "номер",
p.month_name as "месяц",
 case 
        when p.publication_rank <= 3 and e.removal_rank <= 3 then 'высокая активность'
        when p.publication_rank <= 3 and e.removal_rank > 3 then 'много публикаций мало продаж'
        when p.publication_rank > 3 and e.removal_rank <= 3 then 'мало публикаций много продаж'
        else 'низкая активность' 
    end as "тип месяца",
p.published_ads as "опубликованные объявления",
e.removed_ads as "снятые объявления",
round(p.avg_price_m2::numeric,0) as "ср. цена за м² при публикации ₽",
round(e.avg_price_m2::numeric,0) as "ср. цена за м² при продаже ₽",
(e.avg_price_m2 - p.avg_price_m2)::INT as "разница цены ₽",
round(p.avg_m2::numeric,0) as "ср. площадь при публикации",
round(e.avg_m2::numeric,0) as "ср. площадь при продаже",
p.publication_rank AS "ранг публикаций",
e.removal_rank AS "ранг продаж"
from publ p
full join end_publ e using(month_number)




 -- 3 Задача. В каких населённых пунктах Ленинградской области активнее всего продаётся недвижимость и какая именно.
----------------------------------------------------------------------------------------------------------------------------------------------------
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats 
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats f
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
city_stats AS (
    SELECT 
        c.city,
        COUNT(*) as total_ads_in_city
    FROM real_estate.advertisement a
    left join real_estate.flats f using(id)
    LEFT JOIN real_estate.city c USING(city_id)
    WHERE c.city != 'Санкт-Петербург'
    GROUP BY c.city
)
select distinct c.city as "населеннный пункт", 
t.type as "тип нп",
count(a.first_day_exposition) as "объявления",
ROUND(COUNT(CASE WHEN a.days_exposition IS NOT NULL THEN 1 END)::numeric / cs.total_ads_in_city * 100.0, 2) as "доля снятых %",
--round(count(case when days_exposition is not null then 1 end)::numeric / count(id) *100.0 ,2) as "доля снятых %",
round(avg(last_price/total_area)::numeric,0) as "ср. цена ₽ за м²",
round(avg(total_area)::numeric,0) as "ср. площадь м²",
round(avg(a.days_exposition)::numeric,0) as "ср. дней на продажу",
percentile_disc(0.5) within group (order by rooms) as "медиана_комнат",
percentile_disc(0.5) within group (order by balcony) as "медиана_балконов",
percentile_disc(0.5) within group (order by floor) as "медиана_этажности",
round(avg(ceiling_height)::numeric,2) as "ср. высота потолка"
from real_estate.advertisement as a
    left join real_estate.flats f using(id)			
    left join real_estate.city c on c.city_id = f.city_id
    left join real_estate.type t using(type_id)
    inner join filtered_id ff on a.id = ff.id
    inner join city_stats cs on c.city = cs.city
where c.city != 'Санкт-Петербург' 
and first_day_exposition is not null and days_exposition is not null
group by c.city, t.type, cs.total_ads_in_city
order by count(a.first_day_exposition) desc 
limit 20


