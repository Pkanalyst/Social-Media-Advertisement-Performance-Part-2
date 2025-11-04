            Advanced SQL Questions (Focus: Window Functions, Subqueries, and Complex Business Logic) 
			
These questions require more sophisticated SQL techniques and aim to uncover deeper trends and performance metrics.

'1.	Cost Per Event (CPE) Analysis: Calculate the Cost Per Event (CPE) for each campaign,' 
   'defined as total_budget / total_ad_events. Rank the campaigns from best (lowest CPE) to worst.' 
  '(Requires joining ad_event, ads, and campaign and using aggregations).'
  
   select C.campaign_id,C.name,(cast(C.total_budget as numeric)/count(AE.event_id)) as CPE,
   Dense_Rank() over(order by (cast(C.total_budget as numeric)/count(AE.event_id)) asc )
   from campaigns as C inner join ads as AD
   on C.campaign_id=AD.campaign_id inner join ad_events as AE
   on AD.ad_id=AE.ad_id
   group by C.campaign_id,C.name,C.total_budget;
   
'2.	Targeting Efficiency: For a specific campaign, compare the actual user gender of users who interacted with the' 
   'ad versus the target gender defined in the ads table.'
   'Calculate the proportion of events where the target matched the user. (Requires joining ad_event, users, and ads).'
   
  -->(With Where clause)
  
   select AE.ad_id,AD.target_gender,U.user_gender, 
   case when AD.target_gender = U.user_gender then 'Matched'
		else 'Not_Matched'
		end as matched_or_not 
   from ad_events as AE inner join ads as AD
   on AE.ad_id=AD.ad_id inner join users as U
   on AE.user_id=U.user_id
   where (case when AD.target_gender = U.user_gender then 'Matched'
		else 'Not_Matched'
		end )='Matched'
   group by AE.ad_id,AD.target_gender,U.user_gender;

-->(With Having clause)

   select AE.ad_id,AD.target_gender,U.user_gender, 
   case when AD.target_gender = U.user_gender then 'Matched'
		else 'Not_Matched'
		end as matched_or_not 
   from ad_events as AE inner join ads as AD
   on AE.ad_id=AD.ad_id inner join users as U
   on AE.user_id=U.user_id 
   group by AE.ad_id,AD.target_gender,U.user_gender
   having (case when AD.target_gender = U.user_gender then 'Matched'
		else 'Not_Matched'
		end )='Matched';

		
'3.	Daily Event Trend: Calculate the cumulative sum of ad events over time, broken down by date,' 
   'for the highest-budget campaign. This shows the growth trend. (Requires date parsing/extraction and a' 
   'Window Function).'
   
  with highestbudgetcampaign as (select campaign_id from campaigns
    order by total_budget desc
    limit 1
),
dailyeventS as (select date(AE.timestamps) as event_date,count(AE.event_id) as daily_events
    from ad_events as AE inner join ads as AD 
	on AE.ad_id = AD.ad_id
    where AD.campaign_id = (select campaign_id from highestbudgetcampaign) 
    group by date(AE.timestamps)
)
    select event_date,daily_events,
    sum(daily_events) over (order by event_date asc) as cumulative_events_count
    from dailyeventS
order by event_date asc;			  
						  
   
'4.	Geographic Event Density: Identify the top 10 locations that have an event count significantly higher' 
   '(e.g., more than 1 standard deviation) than the average event count across all locations.' 
   '(Requires subqueries or common table expressions (CTEs) and statistical functions).'
   with LocationEvents as (select U.location,count(AE.event_id) as Total_events from users as U inner join ad_events as AE 
                            on U.user_id=AE.user_id
							group by U.location
							order by Total_events desc),
	LocationStats AS (SELECT
        CAST(AVG(Total_events) as NUMERIC) as avg_events,
        STDDEV_POP(Total_events) as stddev_events
    FROM LocationEvents )
	
SELECT LE.location,LE.Total_events
FROM LocationEvents as LE,LocationStats as LS 
WHERE LE.Total_events > (LS.avg_events + LS.stddev_events)
ORDER BY
    LE.Total_events desc
LIMIT 10;						
   
'5.	Target Interest Penetration: Find the campaigns where less than 50% of the interacting users' interests'' 
   'match at least one of the target_interests of the ad. This helps identify poorly targeted campaigns.' 
   '(Requires string manipulation/comparison and aggregation on multiple tables).'

   WITH CampaignInterestMetrics AS (
    SELECT
        C.campaign_id,
        C.name,
        -- Count events where AT LEAST ONE of the user's interests matches an ad target interest
        SUM(CASE
            -- Use EXISTS on a lateral join/subquery to check for a match
            WHEN EXISTS (
                SELECT 1
                -- Unnest breaks the user's comma-separated interests string into separate rows
                FROM UNNEST(STRING_TO_ARRAY(U.interests, ',')) AS user_interest
                -- Check if the ad's target_interests string contains the user's interest (case-insensitive)
                WHERE A.target_interests ILIKE '%' || TRIM(user_interest) || '%'
            ) THEN 1
            ELSE 0
        END) AS matched_event_count,
        
        COUNT(AE.event_id) AS total_event_count
    FROM
        ad_events AS AE
    INNER JOIN users AS U ON AE.user_id = U.user_id
    INNER JOIN ads AS A ON AE.ad_id = A.ad_id
    INNER JOIN campaigns AS C ON A.campaign_id = C.campaign_id
    GROUP BY
        C.campaign_id, C.name
)
SELECT campaign_id,name,matched_event_count,total_event_count,
    (CAST(matched_event_count AS NUMERIC) * 100.0 / total_event_count) AS penetration_rate_percent
FROM CampaignInterestMetrics
WHERE
    -- Filter for campaigns where the penetration rate is less than 50%
    (CAST(matched_event_count AS NUMERIC) * 100.0 / total_event_count) < 50
ORDER BY
    penetration_rate_percent ASC;

                Advanced SQL Questions (New Focus on Sub-queries and CTEs for KPIs & Comparison)
				
These questions use sub-queries/CTEs to calculate complex metrics (like rates or ratios) that are then used in the 
main query for comparison or ranking.

'1.	Low-Efficiency Campaigns: Identify the campaign_id and name of campaigns where the event-per-budget ratio' 
   '(total events / total budget) is in the bottom 25th percentile of all campaigns.'
'o	SQL Technique: Requires a CTE to calculate the ratio for every campaign, and then a window function' 
   '(NTILE or PERCENT_RANK) on the CTE's result set, or a sub-query to find the threshold value.''
   
   with campaignratio as (
    -- 1. calculate the event-per-budget ratio for every campaign
    select C.campaign_id,C.name,
        -- calculate total events per campaign
        count(AE.event_id) as total_events,C.total_budget,
        -- ensure safe division and accurate type casting for the ratio
        cast(count(AE.event_id) as numeric) / C.total_budget as event_per_budget_ratio
    from campaigns as C
    inner join ads as AD on C.campaign_id = AD.campaign_id
    inner join ad_events as AE on AD.ad_id = AE.ad_id
    group by C.campaign_id, C.name, C.total_budget
    having C.total_budget > 0 and count(AE.event_id) > 0 -- avoid division by zero errors
)
select campaign_id,name,total_events,total_budget,event_per_budget_ratio
       from(
        -- 2. apply ntile(4) to rank the ratios into four quartiles
        select
            *,
            -- rank the ratios asc (lowest ratio/efficiency is NTILE 1)
            ntile(4) over (order by event_per_budget_ratio asc) as efficiency_quartile
        from campaignratio) as RANKEDCAMPAIGNS
       where efficiency_quartile = 1 -- filter for the bottom 25th percentile (quartile 1)
       order by event_per_budget_ratio asc;
	
   
'2.Top Platform Event Ratio: For the top 3 ad platforms (by event volume), calculate the ratio of events that are' 
   'click' events versus all other event types combined.''
'o	SQL Technique: Requires CTEs to: 1) Rank the platforms, 2) Calculate total clicks and total events per platform,'''
   'and 3) Join the results to calculate the final ratio.'
   
   with platformranks as (
    -- 1. rank all ad platforms by their total event volume
    select
        AD.ad_platform,
        count(AE.event_id) as total_platform_events,
        -- use rank() to assign a position based on event count
        rank() over (order by count(AE.event_id) desc) as rank_by_events
    from
        ad_events as AE
    inner join ads as AD on AE.ad_id = AD.ad_id
    group by
        AD.ad_platform
),
platformmetrics as (
    -- 2. calculate clicks and total events only for the top 3 platforms
    select
        A.ad_platform,
        -- calculate total 'click' events using conditional aggregation (converted to lowercase 'click')
        sum(case when AE.event_type = 'Click' then 1 else 0 end) as total_clicks,
        count(AE.event_id) as total_events
    from
        ad_events as AE
    inner join ads as A on AE.ad_id = A.ad_id
    inner join platformranks as PR on A.ad_platform = PR.ad_platform
    where
        PR.rank_by_events <= 3 -- filter to include only the top 3 platforms
    group by
        A.ad_platform
)
select
    PM.ad_platform,
    PM.total_clicks,
    -- the denominator is (total events - total clicks), representing "all other event types"
    (PM.total_events - PM.total_clicks) as total_other_events,
    -- 3. calculate the final ratio: clicks / (total events - total clicks)
    cast(PM.total_clicks as numeric) / (PM.total_events - PM.total_clicks) as click_to_other_event_ratio
from
    platformmetrics as PM
where
    (PM.total_events - PM.total_clicks) > 0 -- avoid division by zero
order by
    click_to_other_event_ratio desc;
   
   
'3.	Targeting Mismatch Count: For each ad, calculate the number of events where the user's country (users.country)' 
   'does not match the ad's intended location (users.location if that column is the target location, or assuming' 
   'location in the user table is the location, and joining to see if the ad was targeted for that specific location, if the ads table had a location column). Assuming you can infer targeting logic or use location for comparison.
'o	SQL Technique: Sub-query or CTE to filter and count mis-matched events, then aggregate by ad_id.''
   
   select A.ad_id,A.ad_platform,
     sum(case when U.country <> U.location then 1 else 0 end) as geographic_mismatch_count,
     count(AE.event_id) as total_events_for_ad
     from ad_events as AE inner join ads as A 
	 on AE.ad_id = A.ad_id inner join users as U 
	 on AE.user_id = U.user_id
     group by A.ad_id, A.ad_platform
     order by geographic_mismatch_count desc;
