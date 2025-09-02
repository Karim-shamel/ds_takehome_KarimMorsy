### 1.Overview

The dataset provided covers supplier information, product attributes, price lists over time, purchase orders, and deliveries. It represents a realistic supply chain scenario where the business challenge is to monitor supplier performance and detect issues proactively.

The exercise objectives are fourfold:

-   **Data Quality & EDA (6.A):** Validate the integrity of joins, identify missing values and inconsistencies, and explore seasonality, supplier/country patterns, and shipment dynamics.
    
-   **Predictive Modeling (6.B):** Build a model to predict the likelihood of late deliveries using only features known at order time, with careful handling of temporal splits to avoid leakage.
    
-   **Price Anomaly Detection (6.C):** Normalize prices to EUR and flag unusual price behavior within each supplier–SKU series using a robust and explainable method.
    
-   **SQL Queries (6.D):** Express analytical tasks (late rates, supplier ranking, trailing windows, anomalies, etc.) in SQL with clear, commented queries.
    

An additional extension (Task 7) involved evaluating external predictions, assessing calibration, slice performance, and determining a business-aligned threshold for operational intervention.

  

### 2.EDA & Data Quality

To assess data readiness, I first verified key joins across suppliers, products, price lists, and orders. Primary keys were unique and joins were mostly well-covered, with a few missing values in optional attributes (e.g., hazard class, payment terms). Deliveries were left-joined to orders to retain cancelled and undelivered cases, ensuring no leakage from future data.

Key EDA findings included:

-   **Seasonality:** Order volumes fluctuated by month, with noticeable peaks and troughs. Late delivery rates also varied seasonally, indicating potential external or capacity-driven effects.
    
-   **Supplier and geography:** Late rates differed significantly across supplier countries, suggesting structural disparities in performance.
    
-   **Shipping mode and distance:** Air shipments tended to have lower late rates but higher variance, while long-distance shipments (>5000 km) showed systematically higher delays.
    
-   **Missing/inconsistent values:** A small number of records had missing promised dates or delivery dates; these were excluded or imputed depending on the task.
    

**Potential leakage risks** were identified: actual delivery dates and post-order attributes must be excluded from features. To mitigate this, all predictive features were restricted to those available at order time, and temporal splits were enforced.

  

### 3.Predict late Deliveries

For late delivery prediction, I engineered features available strictly at order time, including: supplier rating/preferred status, ship mode, incoterm, payment terms, hazard flag, promised lead days, order month, quantity, and normalized unit price. Distance buckets were also incorporated where available.

To prevent data leakage, the dataset was split temporally: training on orders up to **2025-03-31** and validating on **2025-04-01 to 2025-06-30**. A balanced Random Forest classifier with 300 estimators was trained.

**Results:**

-   Primary metric **PR-AUC** showed strong performance, supported by ROC-AUC.
    
-   F1 scores were reported at:
    
    -   Fixed threshold (0.5)
        
    -   Best-F1 threshold
        
    -   Capacity-based threshold (top 15% of orders flagged)
        
-   Calibration analysis via reliability diagram and Brier score indicated the model was slightly over-confident, which could be improved with isotonic or Platt scaling.
    
-   Slice analysis showed disparities by ship mode, supplier country, and distance bucket, highlighting specific high-risk regions and transport modes.
    

From a business perspective, flagging the **top 15% of orders** by predicted late probability was recommended as an actionable intervention threshold, balancing operational capacity with predictive precision.

  

### 4.Anomaly Detection

To detect unusual price behavior, all price lists were normalized to **EUR** (assuming a fixed USD→EUR rate of 0.92). Within each `(supplier_id, sku)` series over time, prices were analyzed using a **robust z-score on the logarithm of price**, making the method resilient to scale differences and skew.

Anomalies were flagged when `|z| > 3` (relaxed to 2.5 if none detected). This approach surfaced the top-N anomalies per series, which were summarized in a **Top-20 anomalies table**. In addition, 2–3 time series plots with anomalies highlighted in red dots illustrated both sudden supplier price shifts and potential data entry errors.

The method is simple and explainable, allowing procurement teams to review alerts operationally. Each flagged anomaly should be cross-checked with supplier contracts and market conditions: genuine supplier changes can be approved, while erroneous entries (e.g., incorrect currency or decimal error) can be corrected upstream.

  

### 5.SQL

All SQL solutions are implemented in **`sql/sql_exercise.sql`**, using clear Common Table Expressions (CTEs) and comments for readability. The tasks covered include:

1.  **Monthly late rates** overall and by ship mode (Apr–Jun 2025).
    
2.  **Top 5 suppliers** by order volume in the same window, with their late rates.
    
3.  **Supplier trailing 90-day late rate** before each order date (windowed).
    
4.  **Overlapping price windows** detection for each `(supplier_id, sku)`.
    
5.  **Order value calculation** by attaching the valid price at order date, normalizing to EUR, and computing `order_value_eur`.
    
6.  **Price anomalies** via z-score on ln(price_eur), returning the top 10 |z| values.
    
7.  **Incoterm × distance bucket analysis** of average delay days and counts in the validation window.
    
8.  **Bonus:** Using predictions, bucketed the top 10% high-risk orders and compared late rates vs. low-risk.
    

These queries demonstrate data validation, feature engineering in SQL, anomaly detection, and business-focused aggregation.

  

### 6.External Predictions (task 7)

A set of external predictions (`predictions.csv`) was placed at the repository root and merged with validation labels (Apr–Jun 2025, excluding cancellations). The evaluation followed the same framework as the internal model:

-   **Metrics:** Primary PR-AUC, with ROC-AUC as a secondary check.
    
-   **Thresholding:** Performance reported at a fixed 0.5 cutoff, the best-F1 threshold, and a capacity-based threshold (top 15% of orders flagged). Confusion matrices were provided for each case.
    
-   **Calibration:** A reliability diagram and Brier score were generated, showing that the model’s probabilities were slightly miscalibrated. Potential fixes include isotonic regression or Platt scaling.
    
-   **Slice analysis:** Results were broken down by ship mode, supplier country, and distance buckets. Disparities indicated that some subgroups had systematically lower predictive performance, which would need targeted monitoring.
    
-   **Business threshold:** A top-15% high-risk cutoff was chosen to align with assumed operational review capacity, balancing workload with predictive precision.
    

  

### 7. Summary and recommendations

-   The predictive model achieved strong **PR-AUC**, confirming that order-time features (supplier rating, ship mode, lead days, etc.) contain useful signal for anticipating late deliveries.
-   Using a **capacity-based threshold** (top ~15% of orders by risk) provides a business-aligned intervention point, balancing operational workload with predictive precision.
-   **Supplier and logistics disparities** were evident: certain countries, ship modes, and long-distance shipments consistently had higher late rates, suggesting areas for targeted supplier management or logistics optimization.
-   The **robust z-score anomaly detection** method effectively flagged unusual price changes, enabling procurement teams to separate genuine supplier adjustments from data errors.
-   The **SQL solutions** demonstrated how key analytics (late rates, trailing windows, anomalies, risk bucketing) can be expressed transparently in query form, supporting reproducibility in production pipelines.