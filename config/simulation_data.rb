module SimulationData
 SUNNY=0 # 晴れID
 CLOUDY=1 # 曇ID
 RAINY=2 # 雨ID
 TEMP=100 # 学習データ一時退避配列のID
 TIMESTEP=15 # タイムステップ
 SIM_DAYS=100 # シミュレーション日数
 AGENT_NUM=3
 SUNNY_BORDER=12000.0 # 晴れのボーダー
 CLOUDY_BORDER=5500.0 # 曇のボーダー
 #MIDNIGHT_INTERVAL=12 
 #PENALTY=30
 ### SIMULATION STRATEGY
 NORMAL_STRATEGY=1001
 SECOND_STRATEGY=1002
 THIRD_STRATEGY=1003
 ### 伝送電力量の制限量 
 MAX_TRANSMISSION=2000.0/(60/TIMESTEP) # 伝送電力量の制限(onestep毎の)
 ### Differentialevolutionのパラメータ設定
 MAX_GENS=10
 POP_SIZE_BASE=10
 WEIGHTF=0.8
 CROSSF=0.9
 ## 並列処理の設定
 THREAD=1 # スレッド数の決定
 PROCESSES=4 # プロセス数
end
