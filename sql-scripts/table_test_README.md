=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
=POSTGRES :: replication test
---

## Replication test

::::::::::::::

CREATE TABLE table1 (website varchar(100));
INSERT INTO table1 VALUES ('devuser');
INSERT INTO table1 VALUES ('Created this on the Master on table1');
INSERT INTO table1 VALUES ('pg replication by cicd');

::::::::::::::

CREATE TABLE tables2 (website varchar(100));
INSERT INTO tables2 VALUES ('devuser');
INSERT INTO tables2 VALUES ('Created this on the Master tables2');
INSERT INTO tables2 VALUES ('pg replication by cicd');

::::::::::::::

CREATE TABLE table3 (website varchar(100));
INSERT INTO table3 VALUES ('devuser');
INSERT INTO table3 VALUES ('Created this on the Master table3');
INSERT INTO table3 VALUES ('pg replication by cicd');

::::::::::::::

## Crete the Tables

This script will create three tables (users, products, orders) suitable for basic replication testing. You can modify the columns as needed for your test scenario.

FILE: `tables_test_create.sql`
```sql
-- Table 1: users
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL
);

INSERT INTO users (username, email) VALUES ('testuser', 'testuser@example.com');

-- Table 2: products
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL
);

INSERT INTO products (name, price) VALUES ('Sample Product', 19.99);

-- Table 3: orders
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_id INTEGER REFERENCES products(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO orders (user_id, product_id) VALUES (1, 1);
```

You can use the following psql command in your terminal to check the data just inserted into each table:
```sql
--- query tables
SELECT * FROM users;
SELECT * FROM products;
SELECT * FROM orders;
```

If you run the CREATE TABLE statements and the tables already exist, PostgreSQL will return an error like:
```
ERROR:  relation "users" already exists
```

Without `IF NOT EXISTS: Error`, table not created, script may halt.
With `IF NOT EXISTS: No error`, table is left unchanged if it exists.

Run the script like this:
```
psql -f tables_test_create.sql
```

## Drop the Tables

FILE: `tables_test_drop.sql`
```sql
-- Drop tables for replication test
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS users;
```

Run the script like this:
```
psql -f tables_test_drop.sql
```

::::::::::::::

## Execute the scripts 

Run on the PRIMARY DB

```
-> psql -f tables_test_create.sql
CREATE TABLE
INSERT 0 1
CREATE TABLE
INSERT 0 1
CREATE TABLE
INSERT 0 1
```

Check on PRIMARY and SECONDARY DB

Check remotely

```
psql -h 11.22.33.44 -U dbuser -d mydb -c "\dt"
```

The output should look the same as an indication that data is actively replicated.

```
-> psql -c "\dt"
          List of relations
 Schema |   Name   | Type  |  Owner
--------+----------+-------+----------
 public | orders   | table | postgres
 public | products | table | postgres
 public | users    | table | postgres
(3 rows)


-> psql -c "SELECT * FROM users;"
 id | username |        email
----+----------+----------------------
  1 | testuser | testuser@example.com
(1 row)


-> psql -c "SELECT * FROM products;"
 id |      name      | price
----+----------------+-------
  1 | Sample Product | 19.99
(1 row)


-> psql -c "SELECT * FROM orders;"
 id | user_id | product_id |         order_date
----+---------+------------+----------------------------
  1 |       1 |          1 | 2025-07-15 17:56:56.096274
(1 row)
```