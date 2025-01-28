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