library(coda)
library(rjags)
library(R2jags)
library(mcmcplots)
library(bayestestR)
library(scales)
library(MASS)
library(viridisLite)
library(EnvStats)

source("code/1 Helper functions.R")

#### invterting laser abalition data from Wooller et al., 2021 ####
Wooller <- read.csv("data/Wooller_Data_S3.csv")

Wooller.sr <- Wooller$Sr_Seg01

#dist is in cm, convert to micron
wooller.micron <- Wooller$Dist_Seg01*10000

#forward model simulating micromill results (500 micron band)
mm.bwidth <- 500 #microns
index.wooller.dist<- ceiling(wooller.micron/mm.bwidth) #this is about the same as averaging per 100 data points!

#number of micromill simulations, discarding the last bit of data in the sequence
mm.sim.n <- max(index.wooller.dist) - 1 

mm.sim.avg.Wooller.sr <- rep(0,mm.sim.n)#initiate vectors
mm.sim.sd.Wooller.sr <- rep(0,mm.sim.n)
mm.sim.avg.Wooller.dist <- rep(0,mm.sim.n)

for(i in 1:mm.sim.n){
  temp.sr <- subset(Wooller.sr,index.wooller.dist==i)
  temp.dist <- subset(wooller.micron,index.wooller.dist==i)

  mm.sim.avg.Wooller.sr[i] <- mean(temp.sr)
  mm.sim.sd.Wooller.sr[i] <- sd(temp.sr)
  
  mm.sim.avg.Wooller.dist[i] <- median(temp.dist)#median is less sensitive to potential data gaps
}#takes ~30s 

plot(mm.sim.avg.Wooller.dist, mm.sim.avg.Wooller.sr,type="l")

######tusk dentine extension rate Wooller et al 2021####
wooller.COSr<-read.csv("data/Wooller_isotope_data.csv")

wooller.rate <- rep(NA,27)

#first 2 years of life is neonate (Wooller et al 2021)
#last year is close to death, so these data are omitted
for(i in 3:27){
  test.sub.last <- subset(wooller.COSr$d, wooller.COSr$year==(i-1))
  test.sub <- subset(wooller.COSr$d, wooller.COSr$year==i)
  #d is in an increasing order, so get the first element of last year
  test.comb <- rbind(test.sub,test.sub.last[1])
  wooller.rate[i] <- 10000*(max(test.comb)- min(test.comb))/365 #distance in cm, 365 days in a year
  #results are in microns/day
}

wooller.rate.omit <- na.omit(wooller.rate)
mean.wooller.rate <- mean(wooller.rate.omit)
sd.wooller.rate <- sd(wooller.rate.omit)
hist(wooller.rate[3:27])
plot(3:27,wooller.rate[3:27])

mean.wooller.rate*365*28 #this is close to the total length of the tusk at 1.7 meters

####subsetting the entire data set (150 data points)
sub <- 851:1000
sub.mm.sim.avg.dist <- rev(mm.sim.avg.Wooller.dist[sub])
sub.mm.sim.avg.sr <- rev(mm.sim.avg.Wooller.sr[sub])
sub.mm.sim.sd.sr <- rev(mm.sim.sd.Wooller.sr[sub])

plot(sub.mm.sim.avg.dist, sub.mm.sim.avg.sr, type="l", 
     xlim=c(max(sub.mm.sim.avg.dist),min(sub.mm.sim.avg.dist)))
#back to raw data, which is in the dist
Wooller.sub.raw <- subset(Wooller, (wooller.micron> min(sub.mm.sim.avg.dist -250)) & (wooller.micron< 250 + max(sub.mm.sim.avg.dist)))

######################## inversion with precision 1e-7 ########
Ivo.rate.mean <- mean.wooller.rate #microns per day
Ivo.rate.sd <- sd.wooller.rate

R.sd.mea <- sub.mm.sim.sd.sr
dist.mea <- sub.mm.sim.avg.dist
R.mea <- sub.mm.sim.avg.sr
n.mea = length(sub.mm.sim.avg.sr)

s.intv <- mm.bwidth

max.dist.mea <- max(sub.mm.sim.avg.dist)+ 800 #add some distance before the simulation

#posterior samples of parameters from Misha calibration

a.post <- post.misha.pc2p3$BUGSoutput$sims.list$a[,1]
b.post <- post.misha.pc2p3$BUGSoutput$sims.list$b[,1]
c.post <- post.misha.pc2p3$BUGSoutput$sims.list$c[,1]
post.leng <- length(a.post)

parameters <- c("Ivo.rate","dist", "R1.m","Rin.m", "R2.m","a","b","c","exp.ab",
                "Rin.m.pre","a.m","b.m","c.m","Body.mass.m", "Body.mass", "Rin.m.cps.ac")

dat = list( s.intv = s.intv, max.dist.mea = max.dist.mea, post.leng=post.leng, 
            a.post=a.post, b.post=b.post, c.post=c.post,
            Ivo.rate.mean = Ivo.rate.mean, Ivo.rate.sd = Ivo.rate.sd,
            R.mea = R.mea, dist.mea = dist.mea, R.sd.mea = R.sd.mea, t = 480, n.mea = n.mea)

#Start time
t1 = proc.time()

set.seed(t1[3])
n.iter = 1e4
n.burnin = 5e3
n.thin = 1

#Run it
post.misha.invmamm.i = do.call(jags.parallel,list(model.file = "code/Sr inversion JAGS param mammi.R", 
                                                  parameters.to.save = parameters, 
                                                  data = dat, n.chains=5, n.iter = n.iter, 
                                                  n.burnin = n.burnin, n.thin = n.thin))

#Time taken
proc.time() - t1 #~ 28 hours

save(post.misha.invmamm.i, file = "out/post.misha.invmamm.i.RData")

post.misha.invmamm.i$BUGSoutput$summary

load("out/post.misha.invmamm.i.RData")

#check prior vs posterior parameters
plot(density(post.misha.pc2p3$BUGSoutput$sims.list$a[,1]), col = "black", lwd = 2, type="l",
     xlim = c(0.01,0.04), xlab = "a", ylab= "density")
#lines(density(post.misha.invmamm.param$BUGSoutput$sims.list$a), col = "blue", lwd = 2)
lines(density(post.misha.invmamm.i$BUGSoutput$sims.list$a.m), col = "red", lwd = 2)
#slight deviation from prior
plot(density(post.misha.invmamm.i$BUGSoutput$sims.list$c.m, from = 0, to = 0.01), xlim = c(0, 0.01),ylim = c(0,400),
     lwd=2,col="red", main ="Posterior densities: c", xlab="Parameter estimate")
lines(density(post.misha.pc2p3$BUGSoutput$sims.list$c, from = 0, to = 0.01),
      lwd=2, col="blue")
legend(1.8,0.6, c("Calibration","Case study"),lwd = c(2, 2), col=c("blue","red"))

#save MAPEs and CIs
MAP.a.m <- map_estimate(post.misha.invmamm.i$BUGSoutput$sims.list$a.m)
MAP.a.m[1]
log(2)/MAP.a.m[1]

MAP.b.m <- map_estimate(post.misha.invmamm.i$BUGSoutput$sims.list$b.m)
MAP.b.m[1]
log(2)/MAP.b.m[1]

MAP.c.m <- map_estimate(post.misha.invmamm.i$BUGSoutput$sims.list$c.m)
MAP.c.m[1]
log(2)/MAP.c.m[1]

MCMC.CI.a.m <- hdi(post.misha.invmamm.i$BUGSoutput$sims.list$a.m,0.89)
MCMC.CI.a.m$CI_low
MCMC.CI.a.m$CI_high
log(2)/MCMC.CI.a.m$CI_low
log(2)/MCMC.CI.a.m$CI_high

MCMC.CI.b.m <- hdi(post.misha.invmamm.i$BUGSoutput$sims.list$b.m,0.89)
MCMC.CI.b.m$CI_low
MCMC.CI.b.m$CI_high
log(2)/MCMC.CI.b.m$CI_low
log(2)/MCMC.CI.b.m$CI_high

MCMC.CI.c.m <- hdi(post.misha.invmamm.i$BUGSoutput$sims.list$c.m,0.89)
MCMC.CI.c.m$CI_low
MCMC.CI.c.m$CI_high
log(2)/MCMC.CI.c.m$CI_low
log(2)/MCMC.CI.c.m$CI_high

flux.ratio.m <- post.misha.invmamm.i$BUGSoutput$sims.list$a.m/post.misha.invmamm.i$BUGSoutput$sims.list$b.m
MAP.flux.ratio.m <- map_estimate(flux.ratio.m)
MAP.flux.ratio.m[1]
MCMC.CI.flux.ratio.m <- hdi(flux.ratio.m,0.89)
MCMC.CI.flux.ratio.m$CI_low
MCMC.CI.flux.ratio.m$CI_high

pool.ratio.m <- post.misha.invmamm.i$BUGSoutput$sims.list$c.m/post.misha.invmamm.i$BUGSoutput$sims.list$b.m
MAP.pool.ratio.m <- map_estimate(pool.ratio.m)
MAP.pool.ratio.m[1]
MCMC.CI.pool.ratio.m <- hdi(pool.ratio.m,0.89)
MCMC.CI.pool.ratio.m$CI_low
MCMC.CI.pool.ratio.m$CI_high
