import pandas as pd
import numpy as np
from sqlalchemy import create_engine

# ==== DB정보 ====
DB_USER = ""
DB_PASSWORD = ""
DB_HOST = ""
DB_PORT = "5432"
DB_NAME = "subway"

engine = create_engine(f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}")

# ==== 데이터 불러오기 ====
data=pd.read_sql("select timestamp, visitorid, event, itemid, transactionid, date_only, categoryid, parentid from total_retailrocket_data", engine)

# ==== 고객 ID별 AB 할당 ====
# 고객 ID만 추출
unique_visitors = data['visitorid'].drop_duplicates().reset_index(drop=True) 

# 5:5 비율로 AB 할당
ab_groups = np.random.choice(['A', 'B'], size=len(unique_visitors), p=[0.5, 0.5]) 

# 데이터프라임 형태로 변경
ab_assignment2=pd.DataFrame({'visitorid': unique_visitors,'ab_group':ab_groups}) 

# 원래 데이터와 결합
result_with_ab = pd.merge(data, ab_assignment2, on='visitorid', how='left') 

# ==== 할당 결과 확인 ====
print(f"조인 후 데이터 행수: {len(result_with_ab):,}")
print(f"A그룹 이벤트 수: {(result_with_ab['ab_group'] == 'A').sum():,}")
print(f"B그룹 이벤트 수: {(result_with_ab['ab_group'] == 'B').sum():,}")
print("\n=== 결과 검증 ===")

# ==== 할당된 데이터 DB에 저장 ====
engine = create_engine(f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}")
result_with_ab.to_sql("total_retailrocket_data", engine, if_exists='replace', index=False)
