# DS Take-Home — Package

  
This repository contains my solutions to the data science take-home assignment. 

##   
⚙️ Environment Setup

###   
1. Clone the repository and move into it:  

git clone [<repo-url>](https://github.com/Karim-shamel/ds_takehome_KarimMorsy "https://github.com/Karim-shamel/ds_takehome_KarimMorsy")

[​](https://github.com/Karim-shamel/ds_takehome_KarimMorsy "https://github.com/Karim-shamel/ds_takehome_KarimMorsy")`cd ds_takehome_full_package`

  

### 2. Create virtual enviroment

`python -m venv .venv`  
`source .venv/bin/activate`  # on Linux/macOS  
`.venvScriptsactivate`      # on Windows

### 3. Install dependencies

`pip install -r requirements.txt`

## Running End-to-End

1.  Ensure the provided data files are in the `dataset/` folder.
    
2.  Launch Jupyter:
    
    `jupyter notebook`
    
3.  Open and run the notebooks in order:
    
    -   `notebooks/EDA.ipynb` → exploratory data analysis
        
    -   `notebooks/Model_Anomaly.ipynb` → modeling, anomaly detection, external predictions
        
4.  SQL tasks are implemented in:
    
    -   `sql/sql_exercise.sql`
        
5.  Predictions are saved to and read from:
    
    -   `predictions.csv` at the repository root