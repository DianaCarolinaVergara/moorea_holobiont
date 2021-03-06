#Nicola's Moorea ITS2 analysis
#Almost entirely based on DADA2 ITS Pipeline 1.8 Walkthrough:
#https://benjjneb.github.io/dada2/ITS_workflow.html
#with edits by Carly D. Kenkel and modifications for my data by Nicola Kriefall
#7/23/19

#~########################~#
##### PRE-PROCESSING #######
#~########################~#

#fastq files should have R1 & R2 designations for PE reads
#Also - some pre-trimming. Retain only PE reads that match amplicon primer. Remove reads containing Illumina sequencing adapters

##in Terminal home directory:
##following instructions of installing BBtools from https://jgi.doe.gov/data-and-tools/bbtools/bb-tools-user-guide/installation-guide/
##1. download BBMap package, sftp to installation directory
##2. untar: 
#tar -xvzf BBMap_(version).tar.gz
##3. test package:
#cd bbmap
#~/bin/bbmap/stats.sh in=~/bin/bbmap/resources/phix174_ill.ref.fa.gz

## my adaptors, which I saved as "adaptors.fasta"
# >forward
# AATGATACGGCGACCAC
# >forwardrc
# GTGGTCGCCGTATCATT
# >reverse
# CAAGCAGAAGACGGCATAC
# >reverserc
# GTATGCCGTCTTCTGCTTG

##Note: Illumina should have cut these out already, normal if you don't get any

##primers for ITS:
# >forward
# GTGAATTGCAGAACTCCGTG
# >reverse
# CCTCCGCTTACTTATATGCTT

##Still in terminal - making a sample list based on the first phrase before the underscore in the .fastq name
#ls *R1_001.fastq | cut -d '_' -f 1 > samples.list

##cuts off the extra words in the .fastq files
#for file in $(cat samples.list); do  mv ${file}_*R1*.fastq ${file}_R1.fastq; mv ${file}_*R2*.fastq ${file}_R2.fastq; done 

##gets rid of reads that still have the adaptor sequence, shouldn't be there, I didn't have any
#for file in $(cat samples.list); do ~/bin/bbmap/bbduk.sh in1=${file}_R1.fastq in2=${file}_R2.fastq ref=adaptors.fasta out1=${file}_R1_NoIll.fastq out2=${file}_R2_NoIll.fastq; done &>bbduk_NoIll.log

##only keeping reads that start with the primer
#for file in $(cat samples.list); do ~/bin/bbmap/bbduk.sh in1=${file}_R1_NoIll.fastq in2=${file}_R2_NoIll.fastq k=15 restrictleft=21 literal=GTGAATTGCAGAACTCCGTG,CCTCCGCTTACTTATATGCTT outm1=${file}_R1_NoIll_ITS.fastq outu1=${file}_R1_check.fastq outm2=${file}_R2_NoIll_ITS.fastq outu2=${file}_R2_check.fastq; done &>bbduk_ITS.log
##higher k = more reads removed, but can't surpass k=20 or 21

##using cutadapt to remove adapters & reads with Ns in them
#module load cutadapt 
# for file in $(cat samples.list)
# do
# cutadapt -g GTGAATTGCAGAACTCCGTG -G CCTCCGCTTACTTATATGCTT -o ${file}_R1.fastq -p ${file}_R2.fastq --max-n 0 ${file}_R1_NoIll_ITS.fastq ${file}_R2_NoIll_ITS.fastq
# done &> clip.log
##-g regular 5' forward primer 
##-G regular 5' reverse primer
##-o forward out
##-p reverse out
##-max-n 0 means 0 Ns allowed
##this overwrote my original renamed files 

##did sftp of *_R1.fastq & *_R2.fastq files to the folder to be used in dada2

#~########################~#
##### DADA2 BEGINS #########
#~########################~#

#installing/loading packages:
#if (!requireNamespace("BiocManager", quietly = TRUE))
#  install.packages("BiocManager")
#BiocManager::install("dada2", version = "3.8")
library(dada2)
#packageVersion("dada2")
#I have version 1.10.1 - tutorial says 1.8 but I think that's OK, can't find a version 1.10 walkthrough
library(ShortRead)
#packageVersion("ShortRead")
library(Biostrings)
#packageVersion("Biostrings")

path <- "/Users/nicolakriefall/Desktop/its2/files_rd2" # CHANGE ME to the directory containing the fastq files after unzipping.

fnFs <- sort(list.files(path, pattern = "_R1.fastq.gz", full.names = TRUE))
fnRs <- sort(list.files(path, pattern = "_R2.fastq.gz", full.names = TRUE))

get.sample.name <- function(fname) strsplit(basename(fname), "_")[[1]][1]
sample.names <- unname(sapply(fnFs, get.sample.name))
head(sample.names)

#### check for primers ####
FWD <- "GTGAATTGCAGAACTCCGTG"  ## CHANGE ME to your forward primer sequence
REV <- "CCTCCGCTTACTTATATGCTT"  ## CHANGE ME...

allOrients <- function(primer) {
  # Create all orientations of the input sequence
  require(Biostrings)
  dna <- DNAString(primer)  # The Biostrings works w/ DNAString objects rather than character vectors
  orients <- c(Forward = dna, Complement = complement(dna), Reverse = reverse(dna), 
               RevComp = reverseComplement(dna))
  return(sapply(orients, toString))  # Convert back to character vector
}
FWD.orients <- allOrients(FWD)
REV.orients <- allOrients(REV)
FWD.orients
REV.orients

fnFs.filtN <- file.path(path, "filtN", basename(fnFs)) # Put N-filterd files in filtN/ subdirectory
fnRs.filtN <- file.path(path, "filtN", basename(fnRs))
filterAndTrim(fnFs, fnFs.filtN, fnRs, fnRs.filtN, maxN = 0, multithread = TRUE)

primerHits <- function(primer, fn) {
  # Counts number of reads in which the primer is found
  nhits <- vcountPattern(primer, sread(readFastq(fn)), fixed = FALSE)
  return(sum(nhits > 0))
}
rbind(FWD.ForwardReads = sapply(FWD.orients, primerHits, fn = fnFs.filtN[[1]]), 
      FWD.ReverseReads = sapply(FWD.orients, primerHits, fn = fnRs.filtN[[1]]), 
      REV.ForwardReads = sapply(REV.orients, primerHits, fn = fnFs.filtN[[1]]), 
      REV.ReverseReads = sapply(REV.orients, primerHits, fn = fnRs.filtN[[1]]))
#no primers - amazing

###### Visualizing raw data

#First, lets look at quality profile of R1 reads
plotQualityProfile(fnFs[c(1,2,3,4)])
plotQualityProfile(fnFs[c(90,91,92,93)])

#Then look at quality profile of R2 reads

plotQualityProfile(fnRs[c(1,2,3,4)])
plotQualityProfile(fnRs[c(90,91,92,93)])

#starts to drop off around 220 bp for forwards and 200 for reverse, will make approximately that the cutoff values for filter&trim below

# Make directory and filenames for the filtered fastqs
filt_path <- file.path(path, "trimmed")
if(!file_test("-d", filt_path)) dir.create(filt_path)
filtFs <- file.path(filt_path, paste0(sample.names, "_F_filt.fastq.gz"))
filtRs <- file.path(filt_path, paste0(sample.names, "_R_filt.fastq.gz"))

#changing a bit from default settings - maxEE=1 (1 max expected error, more conservative), truncating length at 200 bp for both forward & reverse, added "trimleft" to cut off primers [20 for forward, 21 for reverse]
out <- filterAndTrim(fnFs, filtFs, fnRs, filtRs, 
                     truncLen=c(220,200), #leaves overlap
                     maxN=0, #DADA does not allow Ns
                     maxEE=c(1,1), #allow 1 expected errors, where EE = sum(10^(-Q/10)); more conservative, model converges
                     truncQ=2, 
                     minLen = 50,
                     #trimLeft=c(20,21), #N nucleotides to remove from the start of each read
                     rm.phix=TRUE, #remove reads matching phiX genome
                     matchIDs=TRUE, #enforce mtching between id-line sequence identifiers of F and R reads
                     compress=TRUE, multithread=TRUE) # On Windows set multithread=FALSE

head(out)
tail(out)

#~############################~#
##### Learn Error Rates ########
#~############################~#

#setDadaOpt(MAX_CONSIST=30) #if necessary, increase number of cycles to allow convergence
errF <- learnErrors(filtFs, multithread=TRUE)
errR <- learnErrors(filtRs, multithread=TRUE)

#sanity check: visualize estimated error rates
#error rates should decline with increasing qual score
#red line is based on definition of quality score alone
#black line is estimated error rate after convergence
#dots are observed error rate for each quality score

plotErrors(errF, nominalQ=TRUE) 
plotErrors(errR, nominalQ=TRUE) 

#~############################~#
##### Dereplicate reads ########
#~############################~#
#Dereplication combines all identical sequencing reads into into “unique sequences” with a corresponding “abundance”: the number of reads with that unique sequence. 
#Dereplication substantially reduces computation time by eliminating redundant comparisons.
#DADA2 retains a summary of the quality information associated with each unique sequence. The consensus quality profile of a unique sequence is the average of the positional qualities from the dereplicated reads. These quality profiles inform the error model of the subsequent denoising step, significantly increasing DADA2’s accuracy.
derepFs <- derepFastq(filtFs, verbose=TRUE)
derepRs <- derepFastq(filtRs, verbose=TRUE)
# Name the derep-class objects by the sample names
names(derepFs) <- sample.names
names(derepRs) <- sample.names

#~###############################~#
##### Infer Sequence Variants #####
#~###############################~#

dadaFs <- dada(derepFs, err=errF, multithread=TRUE)
dadaRs <- dada(derepRs, err=errR, multithread=TRUE)

#now, look at the dada class objects by sample
#will tell how many 'real' variants in unique input seqs
#By default, the dada function processes each sample independently, but pooled processing is available with pool=TRUE and that may give better results for low sampling depths at the cost of increased computation time. See our discussion about pooling samples for sample inference. 
dadaFs[[1]]
dadaRs[[1]]

#~############################~#
##### Merge paired reads #######
#~############################~#

#To further cull spurious sequence variants
#Merge the denoised forward and reverse reads
#Paired reads that do not exactly overlap are removed

mergers <- mergePairs(dadaFs, derepFs, dadaRs, derepRs, verbose=TRUE)
# Inspect the merger data.frame from the first sample
head(mergers[[1]])

summary((mergers[[1]]))

#We now have a data.frame for each sample with the merged $sequence, its $abundance, and the indices of the merged $forward and $reverse denoised sequences. Paired reads that did not exactly overlap were removed by mergePairs.

#~##################################~#
##### Construct sequence table #######
#~##################################~#
#a higher-resolution version of the “OTU table” produced by classical methods

seqtab <- makeSequenceTable(mergers)
dim(seqtab)

# Inspect distribution of sequence lengths
table(nchar(getSequences(seqtab)))
#mostly at 300 bp, which is just what was expected [271-303 bp]

plot(table(nchar(getSequences(seqtab))))

#The sequence table is a matrix with rows corresponding to (and named by) the samples, and 
#columns corresponding to (and named by) the sequence variants. 
#Sequences that are much longer or shorter than expected may be the result of non-specific priming, and may be worth removing

#if I wanted to remove some lengths - not recommended by dada2 for its2 data
#seqtab2 <- seqtab[,nchar(colnames(seqtab)) %in% seq(268,327)] 

table(nchar(getSequences(seqtab)))
dim(seqtab)
plot(table(nchar(getSequences(seqtab))))

#~############################~#
##### Remove chimeras ##########
#~############################~#
#The core dada method removes substitution and indel errors, but chimeras remain. 
#Fortunately, the accuracy of the sequences after denoising makes identifying chimeras easier 
#than it is when dealing with fuzzy OTUs: all sequences which can be exactly reconstructed as 
#a bimera (two-parent chimera) from more abundant sequences.

seqtab.nochim <- removeBimeraDenovo(seqtab, method="consensus", multithread=TRUE, verbose=TRUE)
dim(seqtab.nochim)
#Identified 38 bimeras out of 156 input sequences.

sum(seqtab.nochim)/sum(seqtab)
#0.9989
#The fraction of chimeras varies based on factors including experimental procedures and sample complexity, 
#but can be substantial. 

#~############################~#
##### Track Read Stats #########
#~############################~#

getN <- function(x) sum(getUniques(x))
track <- cbind(out, sapply(dadaFs, getN), sapply(mergers, getN), rowSums(seqtab2), rowSums(seqtab.nochim))
colnames(track) <- c("input", "filtered", "denoised", "merged", "tabled", "nonchim")
rownames(track) <- sample.names
head(track)
tail(track)

write.csv(track,file="its2_reads.csv",row.names=TRUE,quote=FALSE)

#~############################~#
##### Assign Taxonomy ##########
#~############################~#

taxa <- assignTaxonomy(seqtab.nochim, "~/Downloads/GeoSymbio_ITS2_LocalDatabase_verForPhyloseq.fasta",tryRC=TRUE,minBoot=70,verbose=TRUE)
unname(head(taxa))

#to come back to later
saveRDS(seqtab.nochim, file="~/Desktop/its2/mrits2_seqtab.nochim.rds")
saveRDS(taxa, file="~/Desktop/its2/mrits2_taxa.rds")

write.csv(seqtab.nochim, file="mrits2_seqtab.nochim.csv")
write.csv(taxa, file="~/Desktop/its2/mrits2_taxa.csv")

#### Reading in prior data files ####
setwd("~/moorea_holobiont/mr_ITS2")
seqtab.nochim <- readRDS("mrits2_seqtab.nochim.rds")
taxa <- readRDS("mrits2_taxa.rds")

#~############################~#
##### handoff 2 phyloseq #######
#~############################~#

#BiocManager::install("phyloseq")
library('phyloseq')
library('ggplot2')
library('Rmisc')

#import dataframe holding sample information
samdf<-read.csv("mrits_sampledata.csv")
head(samdf)
rownames(samdf) <- samdf$Sample

# Construct phyloseq object (straightforward from dada2 outputs)
ps <- phyloseq(otu_table(seqtab.nochim, taxa_are_rows=FALSE), 
               sample_data(samdf), 
               tax_table(taxa))

ps

#phyloseq object without sample 87, has no data
seq <- read.csv("mrits2_seqtab.nochim_no87.csv")
sam <- read.csv("mrits_sampledata_no87.csv")
row.names(sam) <- sam$Sample
row.names(seq) <- seq$sample
seq2 <- seq[,3:119] #now removing sample name column

ps_no87 <- phyloseq(otu_table(seq2, taxa_are_rows=FALSE), 
                    sample_data(sam), 
                    tax_table(taxa))
ps_no87

#### Alpha diversity #####

#Visualize alpha-diversity - ***Should be done on raw, untrimmed dataset***
#total species diversity in a landscape (gamma diversity) is determined by two different things, the mean species diversity in sites or habitats at a more local scale (alpha diversity) and the differentiation among those habitats (beta diversity)
#Shannon:Shannon entropy quantifies the uncertainty (entropy or degree of surprise) associated with correctly predicting which letter will be the next in a diverse string. Based on the weighted geometric mean of the proportional abundances of the types, and equals the logarithm of true diversity. When all types in the dataset of interest are equally common, the Shannon index hence takes the value ln(actual # of types). The more unequal the abundances of the types, the smaller the corresponding Shannon entropy. If practically all abundance is concentrated to one type, and the other types are very rare (even if there are many of them), Shannon entropy approaches zero. When there is only one type in the dataset, Shannon entropy exactly equals zero (there is no uncertainty in predicting the type of the next randomly chosen entity).
#Simpson:equals the probability that two entities taken at random from the dataset of interest represent the same type. equal to the weighted arithmetic mean of the proportional abundances pi of the types of interest, with the proportional abundances themselves being used as the weights. Since mean proportional abundance of the types increases with decreasing number of types and increasing abundance of the most abundant type, λ obtains small values in datasets of high diversity and large values in datasets of low diversity. This is counterintuitive behavior for a diversity index, so often such transformations of λ that increase with increasing diversity have been used instead. The most popular of such indices have been the inverse Simpson index (1/λ) and the Gini–Simpson index (1 − λ).

plot_richness(ps_no87, x="site", measures=c("Shannon", "Simpson"), color="zone") + theme_bw()

df.div <- data.frame(estimate_richness(ps_no87, split=TRUE, measures =c("Shannon","InvSimpson")))
df.div

df.div$site <- sam$site
df.div$zone <- sam$zone
df.div$site_zone <- sam$site_zone

write.csv(df.div,file="~/moorea_holobiont/mr_ITS2/mrits_diversity.csv") #saving
df.div <- read.csv("~/Desktop/mrits/mrits_diversity.csv") #reading back in 

library(ggplot2)
#install.packages("extrafontdb")
library(extrafontdb)
library(extrafont)
library(Rmisc)
library(cowplot)
library(ggpubr)
#font_import(paths = "/Library/Fonts/")
loadfonts()

diver.sh <- summarySE(data=df.div,measurevar=c("Shannon"),groupvars=c("zone","site"))
diver.si <- summarySE(data=df.div,measurevar=c("InvSimpson"),groupvars=c("zone","site"))

quartz()
gg.sh <- ggplot(diver.sh, aes(x=site, y=Shannon,color=zone,fill=zone,shape=zone))+
  geom_errorbar(aes(ymin=Shannon-se,ymax=Shannon+se),position=position_dodge(0.5),lwd=0.4,width=0.4)+
  geom_point(aes(colour=zone, shape=zone),size=4,position=position_dodge(0.5))+
  xlab("Site")+
  ylab("Shannon diversity")+
  theme_cowplot()+
  scale_shape_manual(values=c(16,15))+
  theme(text=element_text(family="Gill Sans MT"))+
  scale_colour_manual(values=c("#ED7953FF","#8405A7FF"))+
  guides(fill=guide_legend(title="Reef zone"),color=guide_legend(title="Reef zone"),shape=guide_legend(title="Reef zone"))

gg.si <- ggplot(diver.si, aes(x=site, y=InvSimpson,color=zone,fill=zone,shape=zone))+
  geom_errorbar(aes(ymin=InvSimpson-se,ymax=InvSimpson+se),position=position_dodge(0.5),lwd=0.4,width=0.4)+
  geom_point(aes(colour=zone, shape=zone),size=4,position=position_dodge(0.5))+
  xlab("Site")+
  ylab("Inverse Simpson diversity")+
  theme_cowplot()+
  scale_shape_manual(values=c(16,15))+
  theme(text=element_text(family="Gill Sans MT"))+
  scale_colour_manual(values=c("#ED7953FF","#8405A7FF"))+
  guides(fill=guide_legend(title="Reef zone"),color=guide_legend(title="Reef zone"),shape=guide_legend(title="Reef zone"))

gg.sh
gg.si

quartz()
ggarrange(gg.sh,gg.si,common.legend=TRUE,legend="right")

mnw <- subset(df,site=="MNW")
mse <- subset(df,site=="MSE")
tah <- subset(df,site=="TNW")

wilcox.test(Shannon~zone,data=mnw)
#not different
wilcox.test(InvSimpson~zone,data=mnw)
#p = 0.01

wilcox.test(Shannon~zone,data=mse)
#p = 0.001
wilcox.test(InvSimpson~zone,data=mse)
#p = 0.01

wilcox.test(Shannon~zone,data=tah)
#p = 0.04
wilcox.test(InvSimpson~zone,data=tah)
#p = 0.019

#### bar plot ####

top <- names(sort(taxa_sums(ps_no87), decreasing=TRUE))[1:30] #change last 2 numbers to how many you want to plot
ps.top <- transform_sample_counts(ps_no87, function(OTU) OTU/sum(OTU))
ps.top <- prune_taxa(top, ps.top)
plot_bar(ps.top, x="newname",fill="Class") #+ facet_wrap(~ColonyID+Timepoint, scales="free_x")

bot <- names(sort(taxa_sums(ps_no87), decreasing=FALSE))[30:118] #change last 2 numbers to how many you want to plot
ps.bot <- transform_sample_counts(ps_no87, function(OTU) OTU/sum(OTU))
ps.bot <- prune_taxa(bot, ps.bot)
plot_bar(ps.bot, x="newname", fill="Class") #+ facet_wrap(~ColonyID+Timepoint, scales="free_x")

