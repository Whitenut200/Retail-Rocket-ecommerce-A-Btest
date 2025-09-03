create table total_retailrocket_data2 as
with data_event as(
select 
timestamp,
visitorid,
event,
itemid,
transactionid,
ts::date as date_only 
from "Retailrocket_event" re 
  ),
data_category_w_property as(
select
p.timestamp,
p.itemid,
p.value as categoryid,
p.ts::date as date_only,
c.parentid 
from "Retailrocket_property" p 
left join "Retailrocket_category" c on p.value::text=c.categoryid::text
  ),
ab_list as(
select * from public."A/B list2"
  )
select 
A.timestamp, 
A.visitorid,
A.event,
A.itemid,
A.transactionid,
A.date_only,
A.categoryid,
A.parentid,
l.ab_group 
from (
select
eb.timestamp,
eb.event,
eb.visitorid,
eb.itemid,
eb.transactionid,
eb.date_only,
B.categoryid,
B.parentid
from data_event eb left join lateral(
select 
wp.categoryid, 
wp.parentid from data_category_w_property wp 
where eb.date_only>= wp.date_only order by wp.date_only desc limit 1)B on true)A left join ab_list L on A.visitorid=l.visitorid ;
