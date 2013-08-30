# coding: utf-8
require 'awesome_print'

module DifferentialEvolution

  ## 評価関数
  # 0: 購入量
  # 1: 販売量
  # 2: 購入価格
  # 3: 販売価格
  # 4: バッテリー残量
  # 5: 太陽光発電量
  # 6: 需要量
  # 7: 次の太陽光発電量の予測値
  # 8: 次の需要量
  def objective_function(vector)
    ## ここに最小化あるいは最大化を求める関数を定義する 
    buy_power,sell_power,buy_price,sell_price = vector[0],vector[1],vector[2],vector[3]
    battery = vector[4] # %
    solar1,demand1,solar2,demand2 = vector[5],vector[6],vector[7],vector[8]

    cost = battery + solar1 - demand1
    solar2 - demand2
    buy_power * buy_price
    sell_power * sell_price

    puts "#{cost}\t#{vector}\t"
    return cost
    #return vector.inject(0.0) {|sum, x| sum +  (x ** 2.0)}
  end

  ## 特徴ベクトルの生成
  def create_vector(minmax)
    return Array.new(minmax.size) do |i|
      minmax[i][0] + ((minmax[i][1] - minmax[i][0]) * rand())
    end
  end

  def de_rand_1_bin(p0, p1, p2, p3, f, cr, search_space)
    sample = {:vector=>Array.new(p0[:vector].size)}
    cut = rand(sample[:vector].size-1) + 1
    sample[:vector].each_index do |i|
      sample[:vector][i] = p0[:vector][i]
      if (i==cut or rand() < cr)
        v = p3[:vector][i] + f * (p1[:vector][i] - p2[:vector][i])
        v = search_space[i][0] if v < search_space[i][0]
        v = search_space[i][1] if v > search_space[i][1]
        sample[:vector][i] = v
      end
    end
    return sample
  end

  def select_parents(pop, current)
    p1, p2, p3 = rand(pop.size), rand(pop.size), rand(pop.size)
    p1 = rand(pop.size) until p1 != current
    p2 = rand(pop.size) until p2 != current and p2 != p1
    p3 = rand(pop.size) until p3 != current and p3 != p1 and p3 != p2
    return [p1,p2,p3]
  end

  def create_children(pop, minmax, f, cr)
    children = []
    pop.each_with_index do |p0, i|
      p1, p2, p3 = select_parents(pop, i)
      children << de_rand_1_bin(p0, pop[p1], pop[p2], pop[p3], f, cr, minmax)
    end
    return children
  end

  def select_population(parents, children)
    return Array.new(parents.size) do |i|
      (children[i][:cost]<=parents[i][:cost]) ? children[i] : parents[i]
    end
  end

  def search(max_gens, search_space, pop_size, f, cr)
    pop = Array.new(pop_size) {|i| {:vector=>create_vector(search_space)}}
    pop.each{|c| c[:cost] = objective_function(c[:vector])}
    best = pop.sort{|x,y| x[:cost] <=> y[:cost]}.first
    max_gens.times do |gen|
      children = create_children(pop, search_space, f, cr)
      children.each{|c| c[:cost] = objective_function(c[:vector])}
      pop = select_population(pop, children)
      pop.sort!{|x,y| x[:cost] <=> y[:cost]} # コスト最小順に並べる
      best = pop.first if pop.first[:cost] < best[:cost]
      #puts " > gen #{gen+1}, fitness=#{best[:cost]}"
    end
    return best
  end

  ## Module Function
  module_function :search, :create_vector, :objective_function,
    :select_population, :create_children, :select_parents, :de_rand_1_bin
end

## test
if __FILE__ == $0
  # problem configuration
  problem_size = 9
  search_space = [[0,500],[0,500],[30,30],[30,30],[85,85],[0.0,0.0],[80.0,80.0],[0.0,0.0],[68.0,68.0]]
  # algorithm configuration
  max_gens = 200
  pop_size = 30 * problem_size
  weightf = 0.8
  crossf = 0.9
  # execute the algorithm
  best = DifferentialEvolution::search(max_gens, search_space, pop_size, weightf, crossf)
  ap best
  puts "done! Solution: f=#{best[:cost]}, s=#{best[:vector].inspect}"
end
