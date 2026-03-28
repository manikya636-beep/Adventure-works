/* Union of Fact Internet sales and Fact internet sales new 
UNION ALL is used instead of UNION to retain all rows. UNION would remove duplicates which is not desired for sales data.*/

CREATE TABLE Stg_All_Sales AS
SELECT * FROM FactInternetSales
UNION ALL
SELECT * FROM Fact_Internet_Sales_New;


/* 1.Lookup the productname from the Product sheet to Sales sheet. */

CREATE TABLE Stg_Sales_Product AS
SELECT s.*,
    p.EnglishProductName AS ProductName
FROM Stg_All_Sales s
LEFT JOIN DimProduct p
ON s.ProductKey = p.ProductKey;

SELECT ProductName
FROM Stg_Sales_Product
LIMIT 5;

/* 2.Lookup the Customerfullname from the Customer and Unit Price from Product sheet to Sales sheet.
 */

CREATE TABLE Stg_Enriched_Sales AS
SELECT
    s.*,

    -- Customer full name
    CONCAT(
        COALESCE(c.FirstName, ''),
        ' ',
        COALESCE(c.LastName, '')
    ) AS CustomerFullName,

    -- Catalogue price from DimProduct
    CAST(NULLIF(TRIM(p.Unitprice), '') AS DECIMAL(18,2)) AS Product_UnitPrice,

    -- Territory details
    t.SalesTerritoryCountry AS Country,
    t.SalesTerritoryRegion  AS Region

FROM Stg_Sales_Product s
LEFT JOIN DimCustomer c
    ON s.CustomerKey = c.CustomerKey
LEFT JOIN DimProduct p
    ON s.ProductKey = p.ProductKey
LEFT JOIN DimSalesTerritory t
    ON s.SalesTerritoryKey = t.SalesTerritoryKey;

SELECT CustomerFullName, Product_UnitPrice, Country
FROM Stg_Enriched_Sales
LIMIT 5;

/* 3.calcuate the following fields from the Orderdatekey field ( First Create a Date Field from Orderdatekey)
 */
 CREATE TABLE Stg_Date_Transformed AS
SELECT
    s.*,

    -- Calendar fields
    YEAR(Order_Date)        AS Year,
    MONTH(Order_Date)       AS Monthno,
    MONTHNAME(Order_Date)   AS Monthfullname,
    CONCAT('Q', QUARTER(Order_Date)) AS Quarter,
    DATE_FORMAT(Order_Date, '%Y-%b') AS YearMonth,
    DAYOFWEEK(Order_Date)   AS Weekdayno,
    DAYNAME(Order_Date)     AS Weekdayname,

    -- Indian Financial Month (Apr=1 ... Mar=12)
    (MONTH(Order_Date) + 8) % 12 + 1 AS FinancialMonth,

    -- Indian Financial Quarter
    CONCAT('FQ',
        FLOOR(((MONTH(Order_Date) + 8) % 12) / 3) + 1
    ) AS FinancialQuarter

FROM (
    SELECT *,
           STR_TO_DATE(CAST(OrderDateKey AS CHAR), '%Y%m%d') AS Order_Date
    FROM Stg_Enriched_Sales
) s;

SELECT
OrderDateKey,
Order_Date,
Year,
Monthno,
Monthfullname,
FinancialMonth,
FinancialQuarter
FROM Stg_Date_Transformed
LIMIT 5;

/* 4.Calculate the Sales amount usning the columns(unit price,order quantity,unit discount)
 */
 
CREATE TABLE Sales_With_Revenue AS
SELECT *, (UnitPrice * OrderQuantity) - DiscountAmount AS Calculated_SalesAmount
FROM Stg_Date_Transformed;

SELECT Calculated_SalesAmount
FROM Sales_With_Revenue
LIMIT 5;


/* 5.Calculate the Productioncost usning the columns(unit cost ,order quantity)
 */
 
CREATE TABLE Sales_With_Cost AS
SELECT *, (ProductStandardCost * OrderQuantity) AS ProductionCost
FROM Sales_With_Revenue; 

SELECT ProductionCost
FROM Sales_With_Cost
LIMIT 5;

/* 6.Calculate the profit.
 */
CREATE TABLE Final_Master_Sales AS
SELECT *, Calculated_SalesAmount - ProductionCost AS Profit
FROM Sales_With_Cost; 

SELECT
    ROUND(SUM(Calculated_SalesAmount),2) AS Total_Revenue,
    ROUND(SUM(ProductionCost),2) AS Total_Cost,
    ROUND(SUM(Profit),2) AS Total_Profit
FROM Final_Master_Sales;


/* 7.Create a Pivot table for month and sales (provide the Year as filter to select a particular Year)
 Group sales by month. Change the WHERE year value to filter for any specific year. Run the second query to see which years are available in your data.
*/

SELECT DISTINCT Year FROM Final_Master_Sales ORDER BY Year;

-- Monthly sales for a chosen year (change 2013 to any year)
SELECT
    Monthno,
    Monthfullname,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Monthly_Sales
FROM Final_Master_Sales
WHERE Year = 2013
GROUP BY Monthno, Monthfullname
ORDER BY Monthno;
 

/* 8.Create a Bar chart to show yearwise Sales
 Aggregate total sales per year. Use this result as the data source for a bar chart in Power BI / Tableau / Excel.
*/

SELECT
    Year,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Yearly_Sales
FROM Final_Master_Sales
GROUP BY Year
ORDER BY Year;


/* 9.Create a Line Chart to show Monthwise sales
Aggregate sales by YearMonth to show a continuous trend line over time. Ordering by Year then Monthno ensures chronological sequence. */


SELECT
    YearMonth,
    Year,
    Monthno,
    Monthfullname,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Monthly_Sales
FROM Final_Master_Sales
GROUP BY YearMonth, Year, Monthno, Monthfullname
ORDER BY Year, Monthno;


/* 10.Create a Pie chart to show Quarterwise sales
Aggregate sales by quarter. The percentage share column shows each quarter's proportion of total revenue — ideal for a pie chart label. */

SELECT
    Quarter,
    ROUND(SUM(Calculated_SalesAmount), 2) AS Quarterly_Sales,
    ROUND(SUM(Calculated_SalesAmount) * 100
        / SUM(SUM(Calculated_SalesAmount)) OVER (), 2) AS Pct_Share
FROM Final_Master_Sales
GROUP BY Quarter
ORDER BY Quarter;


/* 11.Create a combinational chart (bar and Line) to show Salesamount and Productioncost together
Returns monthly Sales Amount and Production Cost side by side. In your BI tool, plot Sales Amount as bars and Production Cost as a line on the same chart. */
 
SELECT
    YearMonth,
    Year,
    Monthno,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Total_Sales,
    ROUND(SUM(ProductionCost), 2)          AS Total_ProductionCost
FROM Final_Master_Sales
GROUP BY YearMonth, Year, Monthno
ORDER BY Year, Monthno;


/* 12.Build addtional KPI /Charts for Performance by Products, Customers, Region
Three separate views are created so they can be queried independently or connected directly to a BI tool. */
 
/* View 1 — Product Performance */

CREATE VIEW KPI_Product_Performance AS
SELECT
    ProductName,
    COUNT(DISTINCT SalesOrderNumber) AS Total_Orders,
    SUM(OrderQuantity) AS Units_Sold,
    ROUND(SUM(Calculated_SalesAmount), 2) AS Total_Sales,
    ROUND(SUM(ProductionCost), 2) AS Total_Cost,
    ROUND(SUM(Profit), 2) AS Total_Profit,
    ROUND(SUM(Profit) / NULLIF(SUM(Calculated_SalesAmount),0)*100, 2) AS Profit_Margin_Pct
FROM Final_Master_Sales
GROUP BY ProductName
ORDER BY Total_Sales DESC;

/* View 2 — Customer Performance */

CREATE VIEW KPI_Customer_Performance AS
SELECT
    CustomerFullName,
    COUNT(DISTINCT SalesOrderNumber)       AS Total_Orders,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Total_Sales,
    ROUND(SUM(Profit), 2)                  AS Total_Profit,
    ROUND(AVG(Calculated_SalesAmount), 2)  AS Avg_Order_Value
FROM Final_Master_Sales
GROUP BY CustomerFullName
ORDER BY Total_Sales DESC;


/* View 3 — Region Performance */
 
CREATE VIEW KPI_Region_Performance AS
SELECT
    Country,
    Region,
    COUNT(DISTINCT SalesOrderNumber)                                  AS Total_Orders,
    ROUND(SUM(Calculated_SalesAmount), 2)                             AS Total_Sales,
    ROUND(SUM(Profit), 2)                                             AS Total_Profit,
    ROUND(SUM(Profit) / NULLIF(SUM(Calculated_SalesAmount),0)*100, 2) AS Profit_Margin_Pct
FROM Final_Master_Sales
GROUP BY Country, Region
ORDER BY Total_Sales DESC;

/* 13. Create a one or more Dashboards based on the requirement
 */

/* Executive KPI Summary (Single Row) */
 
 SELECT
    ROUND(SUM(Calculated_SalesAmount), 2) AS Total_Revenue,
    ROUND(SUM(ProductionCost), 2) AS Total_Cost,
    ROUND(SUM(Profit), 2) AS Total_Profit,
    ROUND(SUM(Profit)/NULLIF(SUM(Calculated_SalesAmount),0)*100,2) AS Margin_Pct,
    COUNT(DISTINCT SalesOrderNumber) AS Total_Orders,
    COUNT(DISTINCT CustomerFullName) AS Unique_Customers,
    COUNT(DISTINCT ProductName) AS Products_Sold
FROM Final_Master_Sales;


/* Year-over-Year Performance */
 
 SELECT
    Year,
    ROUND(SUM(Calculated_SalesAmount), 2) AS Revenue,
    ROUND(SUM(ProductionCost), 2) AS Cost,
    ROUND(SUM(Profit), 2) AS Profit,
    COUNT(DISTINCT SalesOrderNumber) AS Orders
FROM Final_Master_Sales
GROUP BY Year
ORDER BY Year;

/* Top 10 Products by Revenue */

SELECT
    ProductName,
    ROUND(SUM(Calculated_SalesAmount), 2) AS Revenue,
    ROUND(SUM(Profit), 2) AS Profit,
    SUM(OrderQuantity) AS Units_Sold
FROM Final_Master_Sales
GROUP BY ProductName
ORDER BY Revenue DESC
LIMIT 10;

/* Top 10 Customers by Revenue */

SELECT
    CustomerFullName,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Revenue,
    COUNT(DISTINCT SalesOrderNumber)        AS Orders,
    ROUND(AVG(Calculated_SalesAmount), 2)  AS Avg_Order_Value
FROM Final_Master_Sales
GROUP BY CustomerFullName
ORDER BY Revenue DESC
LIMIT 10;


/* Sales by Country and Region */

SELECT
    Country,
    Region,
    ROUND(SUM(Calculated_SalesAmount), 2) AS Revenue,
    ROUND(SUM(Profit), 2) AS Profit,
    COUNT(DISTINCT SalesOrderNumber) AS Orders
FROM Final_Master_Sales
GROUP BY Country, Region
ORDER BY Revenue DESC;

/* Monthly Trend for Latest Year */

SELECT
    Monthno,
    Monthfullname,
    ROUND(SUM(Calculated_SalesAmount), 2)  AS Revenue,
    ROUND(SUM(Profit), 2)                  AS Profit
FROM Final_Master_Sales
WHERE Year = (SELECT MAX(Year) FROM Final_Master_Sales)
GROUP BY Monthno, Monthfullname
ORDER BY Monthno;
