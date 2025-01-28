# Pushing SQL to its Limits
<br>
<br>
<br>

### High Level Summary
We're going to be pushing SQL (Snowflake) to its limits by applying advanced analytic techniques that are better suited for languages like Python or R. Applying them in SQL forces us to gain a deeper understanding of any algorithms we use instead of relying on pre-built libraries or funcitons. It'll also improve our day to day SQL ability the same way intense exercise at the gym can make day to day stuff like climbing a flight of stairs easier. There's also several use cases where working directly in SQL is faster and cheaper than developing infrastructure for other languages. 
<br>

We will conduct an Exploratory Data Analysis and implement an Associate Rule Learning Algorithm (Equivelence Class Clustering and bottom-up Lattice Traversal). 
<br>

The dataset we're using is a sample of real transaction data from a Brazilian E-Commerce Site. 
<br>

In the EDA, we focused on logistics, inspired by how Amazon dominated the competition by mastering shipping and distribution. We spotted that our customers were generally clustered around two cities: São Paulo and Fortaleza. Our sellers, on the other hand, were mostly in São Paulo. This meant the customers in Fortaleza experienced long shipping times of ¬18 days. Our reccomendation was to open a distribution centre closer to Fortaleza to reduce that average shipping time by 78% to only 4 days. 
<br>

When you order pizza from dominos, before you can checkout you're shown a pop up with items that they think you'd like based on what you've already added to your cart. Product recommendations are a highly effective cross selling technique that 54% of retailers say is the key driver of AOV with 75% of customers more likely to purchase based on personalized recommendations [Liefsight.io]. We applied the ECLAT algorithm to create product recommendations for our store. Our top 3 recommendations are: bed, bath, and tables when furniture decor is purchased; cool stuff when baby products are purchased; and toys when baby products are purchased. 
<br>
<br>
<br>
<br>

## Exploratory Data Analysis
### Stage 1: Exploration
We've got 9 tables to work with and the first thing we need to do is preview each table to get a feel for the data. 
```sql
SELECT * FROM olist_orders LIMIT 10;
```
<br>
<br>

Next we can dive deeper to understand if there's any gaps in the data by looking at each table and seeing if any of the columns have nulls or duplicates. 

<table>
<tr>
<td> Query </td> <td> Output </td>
</tr>
<tr>
<td>

```sql
with column_raw_values as (
    SELECT *
    FROM olist_geolocation
    UNPIVOT(value FOR column_name IN (
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    ))
)
SELECT 
    column_name,
    count(value) as raw_count,
    count(distinct value) as unique_count,
    count_if(value IS NULL) as null_count
FROM column_raw_values
GROUP BY 1
```

</td>
<td>
    
|COLUMN_NAME|RAW_COUNT|UNIQUE_COUNT|NULL_COUNT|
| ---------- | ---------- | --------- | -----------|
|ZIP_CODE_PREFIX|1000163|19015|0|
|LAT|1000163|717372|0|
|LNG|1000163|717615|0|
|CITY|1000163|8011|0|
|STATE|1000163|27|0|


</td>
</tr>
</table>
<br>
<br>
<br>
<br>

### Stage 2: Transformation

It's clear we've got some duplicate values in the geolocation table. In Brazil, zip codes follow a 00000-000 structure. We only have the 5 digit zip code prefix however the coordinate data is for the full zip code which results in multiple rows for the same zip code prefix, with different coordinates. In the other tables the most granular location level we have is zip code prefix. From a visual check on google maps, the zip code prefix districts aren't very large so we can take the average coordinates per zip code prefix without it having much impact on accuracy of location analysis. 

```sql
INSERT overwrite into olist_geolocation
SELECT 
    geolocation_zip_code_prefix as zip_code_previx, 
    avg(geolocation_lat) as lat, 
    avg(geolocation_lng) as lng,
    min(geolocation_city) as city,
    min(geolocation_state) as state
FROM olist_geolocation
GROUP BY 1
```
Both the original data and the transformed data contain some coordinate pairs that have errors and land them somewhere in the middle of the Atlantic. We can remove these rows from the table. 
![image](https://github.com/user-attachments/assets/0babaecb-4c7e-457f-a61c-a6bddbcadd61)
```sql
DELETE FROM olist_geolocation
WHERE geolocation_zip_code_prefix IN (
    18243,
...
    83252
)
```
<br>
<br>


We also have a difference of 775 unique order_ids between the "orders" and "order items" tables. The data comes from a real database so this difference is likely due to desync occuring between the two tables when the snapshot was taken. We're only going to be using orders that appear in both tables in this analysis so we don't need to do any transformations at this stage.
<br>
<br>
<br>
<br>


### Stage 3: Analysis
Brazil is a large country geogrpahically speaking, the largest order distance in the dataset is nearly 4000km or about 2500 miles. One of the biggest areas of improvement for cusotmer satisfaction as well as cost reduction will be the logistics of shipping. This ecommerce site operates as a marketplace and marketplace companies like Amazon have dominated market share by mastering logistics.
<br>
```sql
SELECT 
    o.order_id, 
    o.order_delivered_carrier_date, 
    o.order_delivered_customer_date,
    timestampdiff(hour,o.order_delivered_carrier_date, o.order_delivered_customer_date)/24 
        as delivery_time_days,
    c.customer_zip_code_prefix,
    i.freight_value, 
    s.seller_zip_code_prefix,
    gc.geolocation_lat as customer_lat,
    gc.geolocation_lng as customer_lng,
    gs.geolocation_lat as seller_lat,
    gs.geolocation_lng as seller_lng,
    haversine(customer_lat, customer_lng, seller_lat, seller_lng) as order_distance
FROM olist_orders as o
INNER JOIN olist_customers as c
    ON o.customer_id = c.customer_id
INNER JOIN olist_order_items as i
    ON o.order_id = i.order_id
INNER JOIN olist_sellers as s
    ON i.seller_id = s.seller_id
LEFT JOIN olist_geolocation as gc
    ON c.customer_zip_code_prefix = gc.geolocation_zip_code_prefix
LEFT JOIN olist_geolocation as gs
    ON s.seller_zip_code_prefix = gs.geolocation_zip_code_prefix
WHERE o.order_status = 'delivered'
AND o.order_delivered_carrier_date IS NOT NULL
AND o.order_delivered_customer_date IS NOT NULL
AND customer_lat IS NOT NULL
AND seller_lat IS NOT NULL 
```
<br>

From a visual inspection of the distribution of sellers and customers we can see that customers are clustered around São Paulo and Fortaleza which is to be expected because these areas have high populations. Our sellers, however, are predominantly in São Paulo. One potential path forward could be to open a distribution centre closer to Fortaleza that sellers in São Paulo can hold stock in. This would greatly reduce shipping times as well as freight cost to the business. The distance between São Paulo and Fortaleza is aroudn 2000km, orders of this distance have an average delivery time of 18 days. Opening a distribution centre in Fortaleza would bring the order distance to the sub 200km category which has an average delivery time for 4 days. This presents a 78% reduction in delivery time, increasing customer satisfaction for a large proportion of customers. We can imrpove this delivery time further by implementing route optimisation algorithms. 

![seller map](https://github.com/user-attachments/assets/d0e6b387-b720-4121-ac89-8ec64503fb5e)

![Shipping Graph](https://github.com/user-attachments/assets/9f1e0612-ca16-40fe-b1f6-0e9c8800e7ee)
<br>
<br>
<br>
<br>

## Association Rule Learning

When you're buying a pizza at dominos, before you go to checkout, there's a pop up that recommends products you might be interested in based on what you've already added to your cart. These recommendations are an example of association rule learning algorithms. They're popular in ecommerce to upsell and cross sell items, increasing revenue. 
<br>

We can apply these algorithms to our dataset to find out what products (B) we should recommend when a customer adds product A to their basket. In our case, we have 73 distinct product categories which is granular enough to run this analysis, going deeper into individual products would create too much noise. 
<br>

We're going to use the ECLAT Algorithm which stands for Equivalence Class Clustering and bottom-up Lattice Traversal. It's popular because it's a faster and more efficient version of the Apriori Algorithm since it operates in a depth first manner (vertical) rather than a breadth first manner (horizontal). With Apriori you need to scan the entire database multiple times whereas with ECLAT you just need to interset the tidsets. 
<br>

The first thing we need to do is define our minimum support. The minimum support in this context is the mininmum number of orders a product category needs to have for us to consider it in the analysis, we're going to set this value to 1% of the total orders dynamically using a session variable so that it can expand as the dataset expands with more orders.
```sql
SET minimum_support = (
    SELECT 
        0.01 * count(distinct o.order_id) as occurance
    FROM olist_orders as o
    INNER JOIN olist_order_items as i
        ON o.order_id = i.order_id
    INNER JOIN olist_products as p
        ON i.product_id = p.product_id
)
```
<br>

Next we need to create a frequent itemset table that maps the number of orders per product category. We could directly count the number of orders per product category with a count(distinct) but the efficiency from the ECLAT algorithm comes from generating tidset intersects. Instead, we can create an array of order IDs and use array_size to get the count of them whenever we need to. This approach will have a higher computation time initially but it'll become more efficient as we move onto further iterations. 




<table>
<tr>
<td> Query </td> <td> Output Sample</td>
</tr>
<tr>
<td>

```sql
with order_array as (
SELECT 
    p.product_category_name as product_category,
    array_unique_agg(o.order_id) as order_array
FROM olist_orders as o
INNER JOIN olist_order_items as i
    ON o.order_id = i.order_id
INNER JOIN olist_products as p
    ON i.product_id = p.product_id
GROUP BY 1
)
SELECT 
    product_category,
    array_size(order_array) as occurance
FROM order_array
WHERE occurance > $minimum_support
```

</td>
<td>
    
|PRODUCT_CATEGORY|OCCURANCE|
| ---------- | ---------- |
|cool_stuff|3632|
|pet_shop|1710|
|perfumaria|3162|
|ferramentas_jardim|3518|
|utilidades_domesticas|5884|


</td>
</tr>
</table>

The next step in the process is to create itemset pairs and see how many orders have both product categories in them. For example, we would join cool_stuff and pet_shop together to form an itemset {cool_stuf,pet_shop} and then count how many orders have products from both of these categories in them. In SQL this can get a little difficult but you can do it with a creative approach. 
<br>

To create the itemsets you take the distinct product categories and join them to themselves. You then put these two columns into an array. This array, however, will have duplicates in it as when you do the self join you'll end up with things like {cool_stuff,pet_shop} and {pet_shop,cool_stuff} which is the same itemset. To get around this you can sort the array alphabetically so that both arrays become {cool_stuff,pet_shop} then take only the distinct arrays. 
<br>

We need to find out how many orders contain both product categories. At this point the Apriori algorithm would do another search of the dataset to count this value. Since we're using ECLAT and have already created an array of these orders we can join on each product category array and use array_intersection to get only the orders that appear in both arrays. We can then use array_size to count the number of orders. 

<table>
<tr>
<td> Query </td> <td> Output Sample</td>
</tr>
<tr>
<td>

```sql
...
itemsets as (
    SELECT 
        distinct array_sort(
            array_construct(
                p1.product_category, p2.product_category
            )) as itemset
    FROM (
        SELECT 
            distinct product_category
        FROM first_pass
    ) as p1
    CROSS JOIN (
        SELECT 
            distinct product_category
        FROM first_pass
    ) as p2
    WHERE p1.product_category != p2.product_category
)
SELECT 
    i.itemset, 
    array_size(
        array_intersection(
            o1.order_array,o2.order_array
    )) as occurance
FROM itemsets as i
LEFT JOIN order_array as o1
    ON i.itemset[0] = o1.product_category 
LEFT JOIN order_array as o2
    ON i.itemset[1] = o2.product_category
ORDER BY 2 desc
```

</td>
<td>
    
|ITEMSET|OCCURANCE|
| ---------- | ---------- |
|["bebes","cool_stuff"]|20|
|["bebes","brinquedos"]|19|
|["automotivo","bebes"]|2|


</td>
</tr>
</table>
<br>
<br>

The occurance for all of these itemsets is below the initial minimum support we defined. The reason for this is that the dataset we're using is a sample of the actual full orders dataset. To account for this we're going to recalculate our minimum support at each interation but this time with 2.5% of total orders instead of 1%. This time, since we need ot use the result of a common table expression, we can't set it as a session variable and we have to create another CTE to house it. 
<br>
```sql
...
second_pass_unpruned as (
    SELECT 
        i.itemset, 
        array_size(
            array_intersection(
                o1.order_array,o2.order_array
        )) as occurance
    FROM itemsets as i
    LEFT JOIN order_array as o1
        ON i.itemset[0] = o1.product_category 
    LEFT JOIN order_array as o2
        ON i.itemset[1] = o2.product_category
    ORDER BY 2 desc
),
min_support_2 as (
    SELECT 
        floor(0.025 * sum(occurance)) as min_support
    FROM second_pass_unpruned
)
SELECT 
    s.*
FROM second_pass_unpruned as s
CROSS JOIN min_support_2 as m
WHERE s.occurance > m.min_support
```
<br>

Then we repeat the same itemset logic above with some array manipulation and self joins to create itemsets with three product categories.

```sql
SELECT 
    distinct array_sort(
        array_append(
            s.itemset,t.third_item
    )) as itemset3
FROM second_pass as s
CROSS JOIN (
    SELECT itemset[0] as third_item
    FROM second_pass
    UNION
    SELECT itemset[1] as third_item
    FROM second_pass
) as t
WHERE s.itemset[0] != t.third_item
AND s.itemset[1] != t.third_item 
```
<br>

Next we need to check if the subsets of these three product itemsets are frequent items. One of the Apriori algorithms principles is that all subsets of an itemset must be frequent for that itemset to be considered frequent, this principle applies to ECLAT as well. In our case, all subsets of all itemsets are frequent. 

```sql
SELECT 
    i.itemset3,
    s1.itemset,
    s1.occurance
FROM itemset3 as i
LEFT JOIN second_pass as s1
    ON array_contains(s1.itemset[0], i.itemset3)
    AND array_contains(s1.itemset[1], i.itemset3)
ORDER BY 1,2
```
<br>

Now we will calculate the support for the 3 product category itemset. 

```sql
SELECT
    i.itemset3,
    array_size(
        array_intersection(
            array_intersection(
                o1.order_array,o2.order_array),
            o3.order_array)) as occurance
FROM itemset3 as i
LEFT JOIN order_array as o1
    ON i.itemset3[0] = o1.product_category 
LEFT JOIN order_array as o2
    ON i.itemset3[1] = o2.product_category
LEFT JOIN order_array as o3
    ON i.itemset3[2] = o3.product_category
```
<br>
<br>

For our 3 product itemsets, we don't have any itemsets that have an occurance above our minimum support. This means our frequent itemsets stop at two product categories. We can now generate the itemset lattice:

<table>
<tr>
<td> Query </td> <td> Output Sample</td>
</tr>
<tr>
<td>

```sql
...
lattice_prep as (
SELECT 
    to_array(product_category) as itemset,
    occurance as support
FROM first_pass
UNION
SELECT
    itemset,
    occurance as support
FROM second_pass
)
SELECT 
    *
FROM lattice_prep
ORDER BY array_size(itemset), support desc

```

</td>
<td>
    
|ITEMSET|SUPPORT|
| ---------- | ---------- |
|["beleza_saude"]|8836|
|["bebes","brinquedos"]|19|
|["automotivo","bebes"]|2|


</td>
</tr>
</table>
<br>

With the itemset lattice we can generate association rules along with the confidence and lift of the rule. The confidence of the rule is defined as the SUPPORT(A U B) / SUPPORT(A). The lift is defined as SUPPORT(A U B) / (SUPPORT(A) * SUPPORT(B)) and this measure tells us how the itemsets are correlated with each other.

* A lift value of > 1 means the itemsets are dependent
* A lift value of 1 means the itemsets are independent
* A lift value of < 1 means the itemsets are substitutes

<br> 

```sql
...
confidence_prep as (
    SELECT 
        i.itemset[0] as A,
        i.itemset[1] as B,
        i.itemset,
        i.support
    FROM itemset_lattice as i
    WHERE array_size(i.itemset) > 1
    UNION
    SELECT 
        i.itemset[1] as A,
        i.itemset[0] as B,
        i.itemset,
        i.support
    FROM itemset_lattice as i
    WHERE array_size(i.itemset) > 1
)
SELECT
    p.A,
    p.B,
    ROUND((p.support / i.support)*100,1) as confidence,
    ROUND((p.support / (i.support * i2.support))*100,10) as lift
FROM confidence_prep as p
LEFT JOIN itemset_lattice as i
    ON p.A = i.itemset[0] AND array_size(i.itemset) = 1
LEFT JOIN itemset_lattice as i2
    ON p.B = i2.itemset[0] AND array_size(i2.itemset) = 1
```
<br>

The highest confidence we have for any association rule is 1.1%. This is much lower than typical minimum confidence values of 75% but the reason for that is that we're using a sample so we don't have the complete picture which results in the occurance of itemsets being substantially lower than the occurance of individual items. In reality we would reject these association rules but for the purposes of the project lets take a look at the top 3 non reciprocal rules

|Item A| Item B| Confidence|
|-|-|-|
|moveis_decoracao|cama_mesa_banho|1.1|
|bebes|cool_stuff|0.7|
|bebes|brinquedos|0.7|

In English:

|Item A| Item B| Confidence|
|-|-|-|
|furniture_decor|bed_bath_table|1.1|
|baby|cool_stuff|0.7|
|baby|toys|0.7|

<br>
<br>

Even though our confidence values are low, we can see that these associations make sense in regards to consumer purchasing habits. 
<br>
<br>
<br>
<br>
## Conclusion
In our exploratory data analysis, we found that there was a large gap in geolocation clustering between the majority of our customers and the majority of our sellers. This led to a large increase in delivery times for orders to our second biggest customer territory. To increase customer satisfaction and reduce shipping costs, the recommendation we made was to open a distribution centre closer to this customer hub. This would offer a 78% reduction in delivery time. 
<br>

We used the Equivalence Class Clustering and bottom-up Lattice Traversal Associate Rule Learning algorithm to offer product category recommendations that will increase cross-sell conversions. Our top 3 recommendations are: bed, bath, and tables when furniture decor is purchased; cool stuff when baby products are purchased; and toys when baby products are purchased. 


<br>
<br>
<br>
<br>

## Final Code

```sql
SET minimum_support = (
    SELECT 
        0.01 * count(distinct o.order_id) as occurance
    FROM olist_orders as o
    INNER JOIN olist_order_items as i
        ON o.order_id = i.order_id
    INNER JOIN olist_products as p
        ON i.product_id = p.product_id
);


with order_array as (
    SELECT 
        p.product_category_name as product_category,
        array_unique_agg(o.order_id) as order_array
    FROM olist_orders as o
    INNER JOIN olist_order_items as i
        ON o.order_id = i.order_id
    INNER JOIN olist_products as p
        ON i.product_id = p.product_id
    GROUP BY 1
),
first_pass as (
    SELECT 
        product_category,
        array_size(order_array) as occurance
    FROM order_array
    WHERE occurance > $minimum_support
    AND product_category IS NOT NULL
),
itemsets as (
    SELECT 
        distinct array_sort(
            array_construct(
                p1.product_category, p2.product_category
            )) as itemset
    FROM (
        SELECT 
            distinct product_category
        FROM first_pass
    ) as p1
    CROSS JOIN (
        SELECT 
            distinct product_category
        FROM first_pass
    ) as p2
    WHERE p1.product_category != p2.product_category
),
second_pass_unpruned as (
    SELECT 
        i.itemset, 
        array_size(
            array_intersection(
                o1.order_array,o2.order_array
        )) as occurance
    FROM itemsets as i
    LEFT JOIN order_array as o1
        ON i.itemset[0] = o1.product_category 
    LEFT JOIN order_array as o2
        ON i.itemset[1] = o2.product_category
    ORDER BY 2 desc
),
min_support_2 as (
    SELECT 
        floor(0.025 * sum(occurance)) as min_support
    FROM second_pass_unpruned
),
second_pass as (
    SELECT 
        s.*
    FROM second_pass_unpruned as s
    CROSS JOIN min_support_2 as m
    WHERE s.occurance > m.min_support
),
itemset3 as (
    SELECT 
        distinct array_sort(
            array_append(
                s.itemset,t.third_item
        )) as itemset3
    FROM second_pass as s
    CROSS JOIN (
        SELECT itemset[0] as third_item
        FROM second_pass
        UNION
        SELECT itemset[1] as third_item
        FROM second_pass
    ) as t
    WHERE s.itemset[0] != t.third_item
    AND s.itemset[1] != t.third_item 
    ORDER BY 1
),
subset_eval as (
    SELECT 
        i.itemset3,
        s1.itemset,
        s1.occurance
    FROM itemset3 as i
    LEFT JOIN second_pass as s1
        ON array_contains(s1.itemset[0], i.itemset3)
        AND array_contains(s1.itemset[1], i.itemset3)
),
third_pass as (
    SELECT
        i.itemset3,
        array_size(
            array_intersection(
                array_intersection(
                    o1.order_array,o2.order_array),
                o3.order_array)) as occurance
    FROM itemset3 as i
    LEFT JOIN order_array as o1
        ON i.itemset3[0] = o1.product_category 
    LEFT JOIN order_array as o2
        ON i.itemset3[1] = o2.product_category
    LEFT JOIN order_array as o3
        ON i.itemset3[2] = o3.product_category
),
lattice_prep as (
    SELECT 
        to_array(product_category) as itemset,
        occurance as support
    FROM first_pass
    UNION
    SELECT
        itemset,
        occurance as support
    FROM second_pass
),
itemset_lattice as (
    SELECT 
        *
    FROM lattice_prep
    ORDER BY array_size(itemset), support desc
),
confidence_prep as (
    SELECT 
        i.itemset[0] as A,
        i.itemset[1] as B,
        i.itemset,
        i.support
    FROM itemset_lattice as i
    WHERE array_size(i.itemset) > 1
    UNION
    SELECT 
        i.itemset[1] as A,
        i.itemset[0] as B,
        i.itemset,
        i.support
    FROM itemset_lattice as i
    WHERE array_size(i.itemset) > 1
)
SELECT
    p.A,
    p.B,
    ROUND((p.support / i.support)*100,1) as confidence,
    ROUND((p.support / (i.support * i2.support))*100,10) as lift
FROM confidence_prep as p
LEFT JOIN itemset_lattice as i
    ON p.A = i.itemset[0] AND array_size(i.itemset) = 1
LEFT JOIN itemset_lattice as i2
    ON p.B = i2.itemset[0] AND array_size(i2.itemset) = 1
;
```