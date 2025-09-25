 /* 
Tables used are 
loans - (loans_id, customer_id, loan_type, loan_amount, disbursement_date, interest_rate, tenure_months, status)
Tracks loan details, amount, type, status (active, closed, defaulted).

Payments - (payment_id, loan_id, payment_date, payment_amount, payment_method, is_delayed)
Captures repayment behavior, delays, repayment mode.

Customers - (customer_id, name, gender, dob, join_date, region, income, credit_score)
Stores customer profile with income and credit_score (important for risk).

Branches - (branch_id, region, branch_manager, total_assets)
Each loan is linked to a branch.

Qustion to be asked to dig deeeper

Loan Portfolio Overview – Monthly disbursed loan amounts, outstanding balance.
Customer Profitability Ranking – Top 10 customers by net interest contribution.
Default Rate by Region – % of loans defaulted across branches.
Risk Segment Analysis – Categorize customers (Low/Medium/High risk) by credit score + missed payments.
Churn Detection – Customers with no repayments or activity in the last 6 months.
Average Loan Size by Customer Segment – Compare retail vs SME vs corporate.
Early Warning Indicators – Customers with increasing delays in repayments.
Portfolio Concentration Risk – Industry/sector-wise loan distribution.
Fraud/Anomaly Detection – Customers applying for multiple loans in <7 days.
Interest Income Trend – Monthly growth in earned interest.
Gender-wise Credit Performance – Compare male vs female default % and profitability.
Delinquency Aging Report – Outstanding loans bucketed (30 days, 60 days, 90+ days overdue).
Loan Repayment Patterns – Day-of-week repayment behavior.
Rolling 3-Month NPA (Non-Performing Assets) Trend.
High-Level Risk & Profitability Dashboard – Combine credit score trends, default %, customer profitability. */

-- Monthly Loan Disbursements - Growth of loan book
SELECT
    DATE_TRUNC('month', disbursement_date) AS month,
    SUM(loan_amount) AS total_disbursed,
    COUNT(*) AS loans_issued
FROM loans
GROUP BY DATE_TRUNC('month', disbursement_date)
ORDER BY month;

-- Monthly Interest Income Trend - Profitability of loan book
SELECT
    DATE_TRUNC('month', disbursement_date) AS month,
    SUM(loan_amount * interest_rate / 100) AS interest_income
FROM loans
WHERE status = 'active'
GROUP BY DATE_TRUNC('month', disbursement_date)
ORDER BY month;


/* For a bank, interest income is the primary source of revenue from lending.
Banks don’t call disbursed loan amounts (amount that is lended) as  income — they are assets on the balance sheet (the bank expects to get them back).
You might see loan disbursement rising 📈 but if interest income is flat/declining, it could mean:
More loans are being given at lower interest rates (thin margins).
Higher defaults → less collected interest.

If interest income suddenly dips while loan amounts remain steady, it signals:
Delayed repayments or defaults are increasing.

Different loan types (Retail, SME, Corporate) have different interest yields.
Tracking income trends helps see if the bank is leaning toward high-margin retail loans or low-margin corporate loans.
Strategic Decision Making : 
Management can use it to decide
Do we push more retail loans?
Should we adjust our pricing (interest rates)?
Where do we allocate lending capital next?
*/

-- Net Interest Contribution
SELECT
    c.customer_id,
    c.name,
    SUM(l.loan_amount * l.interest_rate / 100) AS total_interest_expected
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
WHERE l.status = 'active'
GROUP BY c.customer_id, c.name
ORDER BY total_interest_expected DESC
LIMIT 10;

-- Default Rate by Region
SELECT
    c.region,
    COUNT(CASE WHEN l.status = 'defaulted' THEN 1 END) * 100.0 / COUNT(*) AS default_rate_pct
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
GROUP BY c.region
ORDER BY default_rate_pct DESC;

-- Risk Segment Analysis (Credit Score + Missed Payments)
SELECT
    c.customer_id,
    c.name,
    c.credit_score,
    SUM(CASE WHEN p.is_delayed = 1 THEN 1 ELSE 0 END) AS missed_payments,
    CASE
        WHEN c.credit_score < 600 OR SUM(CASE WHEN p.is_delayed = 1 THEN 1 ELSE 0 END) > 3 THEN 'High Risk'
        WHEN c.credit_score BETWEEN 600 AND 700 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_segment
FROM customers c
JOIN loans l ON l.customer_id = c.customer_id
JOIN payments p ON p.loan_id = l.loans_id
GROUP BY c.customer_id, c.name, c.credit_score;

-- Churn Detection (No Payments in Last 6 Months)
SELECT
    c.customer_id,
    c.name,
    MAX(p.payment_date) AS last_payment_date
FROM customers c
JOIN loans l ON l.customer_id = c.customer_id
JOIN payments p ON p.loan_id = l.loans_id
GROUP BY c.customer_id, c.name
HAVING MAX(p.payment_date) < CURRENT_DATE - INTERVAL '6 months';

-- Average Loan Size by Customer Segment
SELECT
    CASE
        WHEN c.income < 50000 THEN 'Retail'
        WHEN c.income BETWEEN 50000 AND 200000 THEN 'SME'
        ELSE 'Corporate'
    END AS segment,
    AVG(l.loan_amount) AS avg_loan_size
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
GROUP BY segment;

-- Early Warning Indicators (Increasing Payment Delays)
SELECT
    l.loans_id,
    c.name,
    COUNT(CASE WHEN p.is_delayed = 1 THEN 1 END) AS total_delays,
    MAX(p.payment_date) AS last_payment
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
JOIN payments p ON p.loan_id = l.loans_id
GROUP BY l.loans_id, c.name
HAVING COUNT(CASE WHEN p.is_delayed = 1 THEN 1 END) >= 3;

-- Portfolio Concentration Risk (Industry/Sector)
SELECT
    sector,
    SUM(loan_amount) AS total_loans,
    100.0 * SUM(loan_amount) / (SELECT SUM(loan_amount) FROM loans) AS portfolio_share_pct
FROM loans
GROUP BY sector
ORDER BY total_loans DESC;

-- Fraud/Anomaly Detection (Multiple Loans in <7 Days)
SELECT
    customer_id,
    COUNT(loans_id) AS loans_taken,
    MIN(disbursement_date) AS first_loan_date,
    MAX(disbursement_date) AS last_loan_date
FROM loans
GROUP BY customer_id
HAVING DATE_PART('day', MAX(disbursement_date) - MIN(disbursement_date)) < 7
   AND COUNT(loans_id) > 1;



