 /* Description: : Loan portfolio analysis
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
Interest Income Trend – Monthly growth in earned interest.
Customer Profitability Ranking – Top 10 customers by net interest contribution.
Default Rate by Region – % of loans defaulted across branches.
Risk Segment Analysis – Categorize customers (Low/Medium/High risk) by credit score + missed payments.
Churn Detection – Customers with no repayments or activity in the last 6 months.
Average Loan Size by Customer Segment – Compare retail vs SME vs corporate.
Early Warning Indicators – Customers with increasing delays in repayments.
Portfolio Concentration Risk – Industry/sector-wise loan distribution.
Fraud/Anomaly Detection – Customers applying for multiple loans in <7 days.
Gender-wise Credit Performance – Compare male vs female default % and profitability.
 */

-- Monthly Loan Disbursements - Growth of loan book
SELECT
    DATE_TRUNC('month', disbursement_date) AS month,
    SUM(loan_amount) AS total_disbursed,
FROM loans
GROUP BY DATE_TRUNC('month', disbursement_date)
ORDER BY month;

-- Monthly Interest Income Trend - Profitability of loan book
SELECT
    DATE_TRUNC('month', disbursement_date) AS month, 
    /*date_trunc Returns the first day of the month with timestamp (e.g., 2025-09-01 00:00:00).
      Keeps year and month together, so you don’t risk merging across years.
      Easier for plotting trends on a timeline.
      whereas, month return only month number higher chances of merging */
    ROUND(SUM(loan_amount * interest_rate / 100, 2) AS interest_income
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
    round(SUM(l.loan_amount * l.interest_rate / 100) - sum(d.deposit_amount* d.interest_rate/100),2) as net_interest_contribution
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id and l.status='closed' 
JOIN deposits d ON d.customer_id = d.customer_id  and d.status='closed'
GROUP BY c.customer_id, c.name
ORDER BY net_interest_contribution DESC
LIMIT 10;

/* Net Interest Contribution = Interest Income (from loans) − Interest Expense (paid on deposits/borrowings)
Interest Income → what the bank earns by lending money (loans, mortgages, credit).
Interest Expense → what the bank pays out to customers on deposits (FD, savings accounts) or to other banks/markets if it borrows funds.
It shows how much the bank earns purely from lending vs. borrowing activities (before other costs like salaries, rent, IT, etc.).
It’s the core profit engine of a bank — how effectively it’s making money from loans after paying for funds.
So NIC tells us how much the bank actually keeps as profit after paying for the money it uses to lend.

Why is NIC important?
Profitability Lens :
If you only look at interest income, you may think the bank is doing well.
But if deposit interest (expense) is also high, the real gain could be much smaller.
NIC reveals the true profitability of lending activities.

Efficiency of Lending Strategy
A rising NIC means the bank is:
Charging higher lending rates (or)
Lowering deposit/borrowing costs.
Falling NIC could mean shrinking margins (e.g., competition forcing low loan rates, but still paying high deposit rates).

Risk-Adjusted Return
Even with high disbursement volumes, if NIC is thin, the bank may not have enough buffer against defaults.
NIC helps balance growth vs safety.

Investor & Regulator Focus
Investors watch NIC/Net Interest Margin (NIM) to judge bank health.
Regulators monitor it to ensure banks aren’t over-exposed by lending at too-thin margins.

Example
Loan disbursed: ₹1,000 Cr @ 10% → Interest Income = ₹100 Cr

Deposits collected: ₹800 Cr @ 6% → Interest Expense = ₹48 Cr
Borrowed funds: ₹200 Cr @ 7% → Interest Expense = ₹14 Cr (borrowsd funds are the one that bank is borrowed from RBI, other banks, etc)

Net Interest Contribution = 100 – (48 + 14) = ₹38 Cr
*/

-- Default Rate by Region (1- default , 0-good to give loan)
SELECT
    c.region,
    round(COUNT(CASE WHEN l.status = 'defaulted' THEN 1 END) / COUNT(*) * 100.0,2) AS default_rate_pct
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
GROUP BY c.region
ORDER BY default_rate_pct DESC;

-- Risk Segment Analysis (Credit Score + Missed Payments)
/* The goal is to identify which customers are high, medium, or low risk for loan default or repayment issues.
Credit score → a standard metric for creditworthiness.
Missed payments → a behavioral indicator (number of delayed payments).
This combination gives a simple risk segmentation that a bank can use to focus monitoring or recovery efforts. */
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

/* Average Loan Size by Customer Segment = total loan amount given to a segment ÷ number of customers in that segment.
Segments can be based on:
Customer type: Retail, SME, Corporate
Risk segment: High, Medium, Low
Region/branch

2️⃣ Why it’s important
Portfolio Composition Insight
Shows which segments are getting larger vs smaller loans.
Example: Corporate loans may have huge average size, Retail smaller loans.
Profitability & Risk Assessment
Larger loans → higher potential interest income but higher risk exposure.
Helps balance growth vs risk in the portfolio.
Customer Strategy & Targeting
If a segment has small average loans but low defaults → opportunity to upsell.
If a segment has high average loans but higher defaults → risk mitigation needed.
Trend Monitoring
Can track average loan size over time by segment to detect changes in lending behavior or strategy shifts.
Example: sudden spike in Retail loan size → may indicate aggressive lending policies.*/

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

/*this is a very important metric in banking and lending, especially for investment and commercial loan portfolios
Portfolio Concentration Risk measures how much your loans (or investments) are concentrated in one customer, industry, sector, or region.
High concentration → risk of large losses if that customer/sector suffers a problem.
Example: If 50% of loans are to the real estate sector, and real estate suffers a downturn, the bank faces big losses.

Risk Diversification
Diversifying loans across multiple industries reduces exposure to sector-specific downturns.

Regulatory Compliance
Banks often have limits on exposure to a single sector or counterparty (regulators don’t want a bank to fail because one industry collapses).

Strategic Decisions
Helps management decide where to allocate future lending.
Example: If Retail is saturated, they may target SME or Corporate loans to balance risk.*/

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

-- Gender-wise Credit Performance
SELECT
    c.gender,
    COUNT(l.loans_id) AS total_loans,
    COUNT(CASE WHEN l.status = 'defaulted' THEN 1 END) AS defaults,
    ROUND(COUNT(CASE WHEN l.status = 'defaulted' THEN 1 END) * 100.0 / COUNT(*), 2) AS default_rate_pct
FROM customers c
JOIN loans l ON c.customer_id = l.customer_id
GROUP BY c.gender;

/*It measures how male vs female customers perform in terms of:
Loan repayment (on-time vs delayed)
Defaults
Average loan size or interest income contribution

Essentially, it’s a segmentation of credit behavior by gender.

Why it’s important
Risk Assessment
Some banks notice trends like:
One gender segment may have lower default rates or better repayment discipline.
This helps in targeting low-risk segments for lending.

Product Design & Targeting
Banks can create tailored loan products for specific segments.
Example: Women-focused small business loans or microloans based on repayment trends.

Regulatory & Social Responsibility
Many regulators encourage banks to track financial inclusion metrics.
Gender-wise analysis shows if loans are equitably distributed and if one segment is underserved.

Marketing & Retention Strategy
Helps in cross-selling or retention:
If a segment is low-risk and profitable → offer premium products.
If a segment shows repayment issues → design support programs or reminders.
