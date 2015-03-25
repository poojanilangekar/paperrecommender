require 'rubygems'
require 'algorithms'

include Containers

q = PriorityQueue.new

q.push(["1234","1234343"], 0.0093243453)
q.push(["rfewrtewrg","wergyertygewr"], 0.123445645)
q.push(["fgdfg","dsgdsfg"],0.435465765)

puts q.pop