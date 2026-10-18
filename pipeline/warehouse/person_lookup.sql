CREATE OR REPLACE VIEW core.person_lookup AS
SELECT 'customer'::text AS entity_kind, customer_id AS person_id,
       family_name,given_name,patronymic,full_name,phone
FROM core.customers
UNION ALL
SELECT 'courier',courier_id,family_name,given_name,patronymic,full_name,NULL::text
FROM core.couriers;
