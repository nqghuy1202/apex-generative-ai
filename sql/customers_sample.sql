--------------------------------------------------------------------------------
-- customers_sample.sql
-- Bảng customers + dữ liệu mẫu để test (APEX 26.1 / DB 26ai)
-- Quy ước dự án: PK cấp bằng SEQUENCE + .NEXTVAL (KHÔNG dùng GENERATED AS IDENTITY)
--------------------------------------------------------------------------------

-- Dọn dẹp nếu chạy lại (an toàn khi test)
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE customers PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;  -- bỏ qua "table does not exist"
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE customers_seq';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -2289 THEN RAISE; END IF; -- bỏ qua "sequence does not exist"
END;
/

--------------------------------------------------------------------------------
-- Sequence cấp PK
--------------------------------------------------------------------------------
CREATE SEQUENCE customers_seq START WITH 1 INCREMENT BY 1 NOCACHE;

--------------------------------------------------------------------------------
-- Bảng customers
--------------------------------------------------------------------------------
CREATE TABLE customers (
  customer_id     NUMBER           NOT NULL,
  full_name       VARCHAR2(120)    NOT NULL,
  email           VARCHAR2(160),
  phone           VARCHAR2(40),
  company         VARCHAR2(120),
  city            VARCHAR2(80),
  country         VARCHAR2(80),
  segment         VARCHAR2(40),     -- VD: Enterprise, SMB, Individual
  status          VARCHAR2(20)
                    DEFAULT 'ACTIVE'
                    CONSTRAINT customers_status_ck
                      CHECK (status IN ('ACTIVE','INACTIVE','PROSPECT')),
  credit_limit    NUMBER(12,2),
  created_at      DATE             DEFAULT SYSDATE,
  CONSTRAINT customers_pk PRIMARY KEY (customer_id),
  CONSTRAINT customers_email_uk UNIQUE (email)
);

--------------------------------------------------------------------------------
-- Dữ liệu mẫu (12 dòng)
--------------------------------------------------------------------------------
INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Nguyễn Văn An',    'an.nguyen@vietsoft.vn',    '+84 901 234 567', 'VietSoft JSC',        'Hà Nội',     'Vietnam',   'Enterprise', 'ACTIVE',   500000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Trần Thị Bình',    'binh.tran@fpt.com.vn',     '+84 902 345 678', 'FPT Software',        'Đà Nẵng',    'Vietnam',   'Enterprise', 'ACTIVE',   750000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Lê Hoàng Cường',   'cuong.le@gmail.com',       '+84 903 456 789', NULL,                  'TP. Hồ Chí Minh', 'Vietnam', 'Individual', 'ACTIVE',   20000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Phạm Thu Dung',    'dung.pham@tikicorp.com',   '+84 904 567 890', 'Tiki Corporation',    'TP. Hồ Chí Minh', 'Vietnam', 'SMB',        'ACTIVE',   120000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Võ Minh Đức',      'duc.vo@shopee.vn',         '+84 905 678 901', 'Shopee VN',           'Hà Nội',     'Vietnam',   'SMB',        'PROSPECT', 80000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Đặng Thị Hoa',     'hoa.dang@vng.com.vn',      '+84 906 789 012', 'VNG Corporation',     'TP. Hồ Chí Minh', 'Vietnam', 'Enterprise', 'INACTIVE', 300000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'John Smith',       'john.smith@acme.com',      '+1 415 555 0142', 'Acme Inc',            'San Francisco', 'USA',     'Enterprise', 'ACTIVE',   1000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Maria Garcia',     'maria.garcia@globex.com',  '+34 612 345 678', 'Globex SL',           'Madrid',     'Spain',     'SMB',        'ACTIVE',   250000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Hiroshi Tanaka',   'tanaka@nippon-tech.jp',    '+81 90 1234 5678','Nippon Tech KK',      'Tokyo',      'Japan',     'Enterprise', 'ACTIVE',   900000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Emma Wilson',      'emma.wilson@outlook.com',  '+44 7700 900123', NULL,                  'London',     'UK',        'Individual', 'PROSPECT', 5000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Bùi Quốc Khánh',   'khanh.bui@momo.vn',        '+84 907 890 123', 'MoMo (M_Service)',    'TP. Hồ Chí Minh', 'Vietnam', 'SMB',        'ACTIVE',   150000000);

INSERT INTO customers (customer_id, full_name, email, phone, company, city, country, segment, status, credit_limit)
VALUES (customers_seq.NEXTVAL, 'Ngô Thị Lan',      'lan.ngo@vietcombank.com.vn','+84 908 901 234', 'Vietcombank',         'Hà Nội',     'Vietnam',   'Enterprise', 'ACTIVE',   2000000000);

COMMIT;

--------------------------------------------------------------------------------
-- Kiểm tra nhanh
--------------------------------------------------------------------------------
SELECT customer_id, full_name, company, country, segment, status, credit_limit
FROM   customers
ORDER  BY customer_id;
