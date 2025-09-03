import pandas as pd

# DB정보 
DB_USER = ""
DB_PASSWORD = ""
DB_HOST = ""
DB_PORT = "5432"
DB_NAME = "subway"

engine = create_engine(f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}")

# 데이터 로드
data = pd.read_csv("Retailrocket A-B/0. raw_data/events.csv")
data2 = pd.read_csv("Retailrocket A-B/0. raw_data/category_tree.csv")
data3 = pd.read_csv("Retailrocket A-B/0. raw_data/item_properties_part1.csv")
data4 = pd.read_csv("Retailrocket A-B/0. raw_data/item_properties_part2.csv")

# 데이터 결합
# 유니온
data_all = pd.concat([data3, data4], ignore_index=True)

# categoryid에 해당하는부분만 추출
data_catagroy = data_all[data_all['property'] == 'categoryid']
data2["categoryid"] = data2["categoryid"].astype(str).str.strip()

# 병합
data_catagory = pd.merge(data2, data_catagroy, left_on="categoryid", right_on="value", how="right")

# 날짜 전처리
# timestamp -> date
data["timestamp"] = pd.to_datetime(data["timestamp"], unit="ms")
data_catagory["timestamp"] = pd.to_datetime(data_catagory["timestamp"], unit="ms")
data["date_only"] = data["timestamp"].dt.date
data_catagory["date_only"] = data_catagory["timestamp"].dt.date

print("=== 데이터 준비 완료 ===")
print(f"data 행수: {len(data)}")
print(f"data_catagory 행수: {len(data_catagory)}")

def date_based_join(events_df, category_df):
    """
    날짜 기준 과거값 조인 함수
    - category의 날짜가 event 날짜보다 작거나 같으면 그 값을 가져옴
    - 가장 가까운 과거값을 선택
    """
    results = []
    
    # itemid별로 처리
    for item_id in events_df['itemid'].unique():
        # 해당 itemid의 이벤트 데이터
        item_events = events_df[events_df['itemid'] == item_id].copy()
        
        # 해당 itemid의 카테고리 데이터
        item_categories = category_df[category_df['itemid'] == item_id].copy()
        
        if len(item_categories) == 0:
            # 카테고리 정보가 없으면 NaN으로 채움
            item_events['categoryid'] = None
            item_events['parentid'] = None
            results.append(item_events)
            continue
        
        # 날짜 기준 정렬
        item_events = item_events.sort_values('date_only').reset_index(drop=True)
        item_categories = item_categories.sort_values('date_only').reset_index(drop=True)
        
        # 각 이벤트에 대해 적절한 카테고리 찾기
        for idx, event_row in item_events.iterrows():
            event_date = event_row['date_only']
            
            # event_date보다 작거나 같은 카테고리 데이터들
            valid_categories = item_categories[item_categories['date_only'] <= event_date]
            
            if len(valid_categories) > 0:
                # 가장 가까운 과거값 (가장 최근 날짜)
                latest_category = valid_categories.iloc[-1]
                item_events.loc[idx, 'categoryid'] = latest_category['categoryid']
                item_events.loc[idx, 'parentid'] = latest_category['parentid']
            else:
                # 과거값이 없으면 NaN
                item_events.loc[idx, 'categoryid'] = None
                item_events.loc[idx, 'parentid'] = None
        
        results.append(item_events)
        
        # 진행 상황 출력 (1000개마다)
        if len(results) % 1000 == 0:
            print(f"처리 완료: {len(results)}개 아이템")
    
    return pd.concat(results, ignore_index=True)

# 조인 실행
print("\n=== 날짜 기준 조인 시작 ===")
result = date_based_join(data, data_catagory)

print(f"\n=== 조인 완료 ===")
print(f"결과 행수: {len(result)}")
print(f"categoryid NaN 개수: {result['categoryid'].isna().sum()}")
print(f"parentid NaN 개수: {result['parentid'].isna().sum()}")

# 결과 샘플 확인
print("\n=== 결과 샘플 (첫 10행) ===")
print(result[['itemid', 'date_only', 'categoryid', 'parentid']].head(10))

# 특정 itemid로 결과 확인
sample_item = result['itemid'].iloc[0]
print(f"\n=== itemid {sample_item} 결과 확인 ===")
sample_result = result[result['itemid'] == sample_item][['itemid', 'date_only', 'categoryid', 'parentid']].head()
print(sample_result)

# 해당 itemid의 원본 카테고리 데이터도 확인
print(f"\n=== itemid {sample_item} 원본 카테고리 데이터 ===")
sample_category = data_catagory[data_catagory['itemid'] == sample_item][['itemid', 'date_only', 'categoryid', 'parentid']]
print(sample_category)

# DB 저장
result_with_ab.to_sql("total_retailrocket_data", engine, if_exists='replace', index=False)
