library(ggplot2)
library(data.table)
library(gridExtra)
library(tidyr)
library(pbapply)
library(ggh4x)
library(forcats)
library(ggforce)

dt<-fread("data/qtls_10cMwindow_fixed_overlap_5.5cm_march18.txt")
highs<-dt[,.SD[rsq==max(rsq)],by = .(trtgroup,type)]
colnames(highs)[3]<-'txname'
#had to pick 2 different transcripts for SA cis and SW cis so they arent the same
#dt[trtgroup == "SW"&type == "cis",.SD, .SDcols=names(dt)][order(-rsq)]
#sa cisAt2g21640
#silwet cis At2g20670
highs
highs<-highs[!((trtgroup %in% c("SA","SW")) & (type == "cis")),]
high1<-dt[type=="cis"&trtgroup == "SA"& txname=="At2g21640",]
high2<-dt[type=="cis"&trtgroup == "SW"& txname=="At2g20670",]
highs<-rbind(highs,high1,high2)
#get transcript abundance data
pheno<-fread("data/rils_pheno.txt")
#read in map of genotypes for the rils, make names compatible 
geno<-fread("data/geno_editednames.txt")
#read in gmap
igmap<-fread("data/imputed_gmap_final.txt")
gmap<-fread("data/original/BayxSha_gmap.csv")
gmap<-gmap[,marker := gsub("\\..*","",marker)]
#if transcript does not have genotype information, 
#just get the genotype information of the nearest marker
highs[, closest_marker_qtl := gmap[.SD, on = .(chr = qtl_chr, pos = qtl_pos), roll = "nearest", x.marker]]

# Define the function
find_closest_marker <- function(highs, igmap, gmap) {
  # Add an empty column for the closest marker based on tx_pos
  highs[, closest_marker_tx := NA_character_]
  
  for (i in 1:nrow(highs)) {
    # Extract txname for the current row
    current_txname <- highs$txname[i]
    
    # Find the corresponding tx_pos from igmap
    tx_pos <- igmap[marker == current_txname]$pos
    
    # Extract tx_chr for the current row to filter gmap
    tx_chr <- igmap[marker == current_txname]$chr
    
    # Filter gmap for the current chromosome
    gmap_chr <- gmap[chr == tx_chr]
    
    # If gmap_chr is not empty, proceed
    if (nrow(gmap_chr) > 0) {
      # Calculate the absolute difference between tx_pos and each pos in gmap_chr
      gmap_chr[, diff := abs(tx_pos - pos)]
      
      # Find the row with the minimum difference
      closest_row <- gmap_chr[which.min(diff)]
      
      # Update the closestmarker_tx column in highs for the current row
      highs$closest_marker_tx[i] <- closest_row$marker
    }
  }
  
  return(highs)
}

# Example usage
highs_updated <- find_closest_marker(highs, igmap, gmap)

#function to merge the phenotype and genotype information based on the qtl data
merge_pheno_geno<-function(qtldt){
  pbapply(qtldt,1,FUN = function(row){
    #row<-highs[1,]
    tx <- as.character(row[3])
    trtment<-row[4]
    nearestmarker_tx <-as.character(row[10])
    group <- as.character(row[1])
    regtype <- as.character(row[2])
    qtlpos<- as.character(row[7])
    qtlmarker<-as.character(row[9])
    gene_tx <- pheno[, .(ID,treatment, transcript = get(tx))]
    gene_geno <- geno[, .(ID, genotype = get(qtlmarker))]
    genedt <- merge(gene_tx, gene_geno)
    genedt$txname<-rep(tx)
    genedt$closestmarkertotx<-rep(nearestmarker_tx)
    genedt$trtgroup<-rep(group)
    genedt$type<-rep(regtype)
    genedt$qtlmarker<-rep(qtlmarker)
    genedt$qtlpos<-rep(qtlpos)
    genedt$chr<-rep(as.character(row[8]))
    return(genedt)
  })
}
highsgeneinfolist<-merge_pheno_geno(highs_updated)
highsgeneinfo<-rbindlist(highsgeneinfolist)

highsgeneinfo[genotype==-1]<-NA
highsgeneinfo<-na.omit(highsgeneinfo)

##########################################################################################################
#environment single gene plots
##########################################################################################################
unique_combinations<-unique(highsgeneinfo[,.(trtgroup,txname,type)])
highsnodelta<-highsgeneinfo[treatment!='delta']
highsnodelta<-highsnodelta[order(match(trtgroup,c("SA","SW","delta","SA SW","SA delta","SW delta","SA SW delta")))]
ggplot(highsnodelta, aes(x=treatment, y=transcript, color=genotype)) +
  geom_point(aes(group=interaction(ID,txname)),alpha = 0.3) +
  facet_grid2(fct_relevel(trtgroup,"SA","SW","delta","SA delta","SW delta","SA SW","SA SW delta")~type,scales = 'free_y',independent = 'y')+
  theme_bw()+
  scale_color_manual(values = c("#56B4E9","#CC79A7"))+
  theme(
    legend.position = "none",
    text = element_text(size = 9),
    axis.text = element_text(size = 9))+
  ylab("Transcript abundance")+
  xlab("Treatment")+
  stat_summary(
    data = subset(highsnodelta, genotype == "C"),
    aes(group=genotype), 
    fun=mean, geom="line",
    size=0.8, 
    color="#56B4E9"
  ) +
  # Average line for the second genotype group
  stat_summary(
    data = subset(highsnodelta, genotype == "L"),
    aes(group=genotype), 
    fun=mean, geom="line", 
    size=0.8, 
    color="#CC79A7" # Adjust the color to the dark pink you prefer
  ) 


##single gene expression over environment for SA specific genes###
genes<-c("ID","treatment","At3g26830",
         "At2g14610","At2g40750","At2g26020")
rils<-fread("data/rils_pheno.txt")
rils<-rils[,.SD,.SDcols = genes]
parents<-fread("data/parents_pheno_corrected.txt")
parents<-parents[,lapply(.SD,mean),by = .(treatment,ID)]
parents$rep<-NULL
parents<-parents[,.SD,.SDcols = genes]
genesdt<-rbind(rils,parents)
genesdt<-genesdt[treatment != "delta"]

geneslong<-melt(genesdt,id = c("ID","treatment"),variable.name = "transcript")
ggplot(geneslong,aes(x = treatment, y = value, group = ID))+
  geom_line(alpha = 0.2, linewidth = 0.5)+
  facet_wrap(~transcript, scales = "free_y",
             labeller = as_labeller(c(At3g26830 = "PAD3 (AT3G26830)",
                          At2g14610 = "PR1 (AT2G14610)",
                          At2g40750 = "WRKY54 (AT2G40750)",
                          At2g26020 = "PDF1.2b (AT2G26020)")))+
  theme_bw()+
  theme(panel.background = element_blank(),
        strip.text = element_text(size=7))+
        ylab("Transcript Abundance")+
        xlab("Treatment")+
  geom_line(data=geneslong[ID=="Bay"],aes(x=treatment,y=value,group=ID),size=2,colour="#56B4E9")+
  geom_line(data=geneslong[ID=="Sha"],aes(x=treatment,y=value,group=ID),size=2,colour="#CC79A7")










geneplots<-lapply(highsgeneinfolist,FUN = function(genetable){
  genetable[genotype==-1]<-NA
  genetable<-na.omit(genetable)
  genedtmean <- na.omit(genetable[, mean(transcript), by = .(treatment, genotype)])
  colnames(genedtmean)[3] <- "transcript_abundance"
  gpl<-ggplot(genedtmean,aes(x=genotype,y=transcript_abundance,color=treatment))+
    geom_line(aes(group=treatment))+
    ggtitle(paste(genetable$trtgroup,"\n",genetable$txname))+
    theme(plot.title = element_text(size=6,face = 'bold'))
  
  return(gpl)
})
pdf("single_gene_plots_collapsedqtls_final.pdf", width = 8, height = 14) # Adjust dimensions as needed
do.call("grid.arrange", c(geneplots, ncol = 2, top = "Gene Expression Plots"))
dev.off() # Close the PDF device


# This line adds facets, in a grid organized by 'trtgroup' and 'type'
# Replace with your actual main title
##########################################################################################################
#genotype single gene plots
##########################################################################################################
highs_avg<-highsgeneinfo[genotype!="-1",mean(transcript),by=c('treatment','genotype','type','trtgroup')]
highs_avg1<-highs_avg[,.(ID,treatment,genotype,txname,trtgroup,type,avg_abundance)]
custom_colors <- c("SA" = "#377EB8", "delta" = "#E6550D", "SW" = "#4DAF4A")
ggplot(highs_avg1, aes(x=genotype, y=avg_abundance, color=treatment)) +
  geom_line(aes(group=treatment)) +
  facet_grid2(fct_relevel(trtgroup,"SA","SW","delta","SA SW","SA delta","SW delta","SA SW delta")~type,scales = 'free_y',independent = 'y')+
  theme_bw()+
  scale_x_discrete(labels=c('C'="Bay","L"="Sha"))+
  scale_color_manual(values = c(custom_colors))+
  theme(legend.position = 'none',
        text = element_text(size = 9),
        axis.text = element_text(size = 9))+
  ylab("transcript abundace")
##########################################################################################################
# Plot for non-delta treatments
p1 <- ggplot(subset(highs_avg1, treatment != "delta"), aes(x=genotype, y=avg_abundance, color=treatment)) +
  geom_line(aes(group=treatment)) +
  facet_grid2(fct_relevel(trtgroup,"SA","SW","delta","SA SW","SA delta","SW delta","SA SW delta") ~ type,scale= 'free') +
  theme_bw() +
  scale_x_discrete(labels=c('C'="Bay","L"="Sha")) +
  scale_color_manual(values = custom_colors) +
  theme(legend.position = 'none',
        text = element_text(size = 9),
        axis.text = element_text(size = 9)) +
  ylab("transcript abundance")

# Plot for delta treatment
p2 <- ggplot(subset(highs_avg1, treatment == "delta"), aes(x=genotype, y=avg_abundance, color=treatment)) +
  geom_line(aes(group=treatment)) +
  facet_grid2(fct_relevel(trtgroup,"SA","SW","delta","SA SW","SA delta","SW delta","SA SW delta") ~ type,scale = 'free') +
  theme_bw() +
  scale_x_discrete(labels=c('C'="Bay","L"="Sha")) +
  scale_color_manual(values = custom_colors) +
  theme(legend.position = 'none',
        text = element_text(size = 9),
        axis.text = element_text(size = 9)) +
  ylab("transcript abundance")

# Combine the plots
grid.arrange(p1,p2, ncol=2)















avg_data <- highsgeneinfo[treatment != 'delta',.(ID,transcript,treatment,txname,genotype,closestmarkertotx,trtgroup,type,qtlmarker),] 
avg_data<-avg_data[,mean(transcript),by=.(genotype,txname,trtgroup,type,treatment)]
colnames(avg_data)[6]<-"avg_transcript"  
#need to manually go through and clean out
unique_combinations<-unique(avg_data[,.(trtgroup,txname,type)])
# Open PDF file for saving plots
pdf("Average_Plots.pdf", width=4, height=4)
# Loop over each unique factor in the column (replace 'your_column' with the name of the column)
for(i in 1:nrow(unique_combinations)) {
  # Subset data for the specific factor
  sub_data <- avg_data[trtgroup == unique_combinations[i,"trtgroup"]&type== unique_combinations[i,"type"]&txname==unique_combinations[i,"txname"]]
  trt<-sub_data$trtgroup[1]
  cisortrans<-sub_data$type[1]
  transcriptname<-sub_data$txname[1]
  # Generate the ggplot for each subset
  p <- ggplot(sub_data, aes(x=treatment, y=avg_transcript, color=genotype)) +
    geom_point() +
    geom_line(aes(group=genotype))+
    ggtitle(paste("Average Plot for", transcriptname,"\nTreatment Groups: ",trt,"\nType:",cisortrans))
  print(p)
}
dev.off()









































saswmax<-max(highsdtmean[treatment!="delta",transcript_abundance])
saswmin<-min(highsdtmean[treatment!="delta",transcript_abundance])
deltamax<-max(highsdtmean[treatment=="delta",transcript_abundance])
deltamin<-min(highsdtmean[treatment=="delta",transcript_abundance])
scalenum<-(saswmax-saswmin)/(deltamax-deltamin)
shiftnum<-saswmin-deltamin
#function to scale the secondary axis
scale_function<-function(x,scalevalue,shiftvalue){
  return ((x-shiftvalue)/scalevalue)
}
inv_scale_function<-function(x,scalevalue,shiftvalue){
  return ((x)*scalevalue+shiftvalue)
}
#change data from long to wide
highsdtmean_wide<-spread(highsdtmean,treatment,transcript_abundance)
highsdtmean


p <- ggplot(genedtmean_wide, aes(x = genotype, y = SA))+
  geom_line(aes(group =1,color = "SA"))+
  geom_line(aes(y = SW, color = "SW",group = 1))+
  geom_line(aes(y = inv_scale_function(delta,scalenum,shiftnum),group = 1,color = "Delta"))+
  scale_y_continuous(,sec.axis = sec_axis(~scale_function(.,scalenum,shiftnum),name="Delta Scale"))+
  ggtitle(paste("Gene:", gene, "Group:", group,"\n", "Type:",regtype,"Marker:",marker))+
  theme(plot.title = element_text(size = 11, face = "bold"))+
  ylab("Transcript Abundance")


return(p)
}

# Apply the create_gene_plot function to each row of highsdt and get a list of plots
plot_list <- apply(highsdt, 1, create_gene_plot)

# Save the grid of plots to a PDF file
pdf("single_gene_plots_fixed_final.pdf", width = 8, height = 14) # Adjust dimensions as needed
do.call("grid.arrange", c(plot_list, ncol = 2, top = "Gene Expression Plots"))
dev.off() # Close the PDF device
