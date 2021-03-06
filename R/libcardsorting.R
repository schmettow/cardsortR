## Library for Card Sorting data
library(RBGL) ## BioConductor package providing an implementation of graph theory
library(plyr)
library(dplyr)
library(tidyr)
library(reshape2)
library(gplots) ## check me
library(ggplot2)
library(RColorBrewer)
library(ggdendro)
#library(reshape)
library(grid)


## ~~~~~~~~~~~~~~~~~~~##
## Reading raw data ####
## ~~~~~~~~~~~~~~~~~~~##

read.lol<-function(node,graph=NULL,root="ROOT",mode="down",weight=1){
  ##  RECURSIVE
	## makes  a graph from a list of list, by default edges are downwards to the leaves
	if(is.null(graph)) graph<-new("graphNEL",nodes=root,edgemode="directed")
	if(length(node)>0){
		
		for(n in 1:length(node)){
			thisnode <- node[[n]]
			if(!is.list(thisnode)){
				nodename <- as.character(thisnode)
				try(graph <- addNode(nodename,graph))
			} else {
				nodename <- as.character(names(node)[n])
				try(graph <- addNode(nodename,graph))
				## here the recursive call
				graph <- read.lol(thisnode,graph,nodename,mode)
			}
			if(mode=="bidir" || mode=="up")    graph <- addEdge(nodename,root,graph,1)
			if(mode=="bidir" || mode=="down") 	graph <- addEdge(root,nodename,graph,0)  
			#print(paste(root,nodename,1))
		}
	} else {
		warning("Unexpected terminal node, recovered, but check your data file")
	}
	graph
}


read.memtable <- function(memtab){
  ## makes a list of lists from a membership table as provided by concept Codify
  ## limited to single level card sorts
  ##
  ## memtable is required to have the following structure:
  ## |Subject|Group|1|2|...|n|
  ## 1 = is in group, 0 otherwise
  memtab$Subject = as.character(memtab$Subject)
  memtab$Group = as.character(memtab$Group)
  LOL = list()
  
  for (s in unique(memtab$Subject)){
    this.subject = filter(memtab, Subject == s)
    for (g in unique(this.subject$Group)){
      this.group = filter(this.subject, Group == g)[c(-1, -2)]
      this.items = colnames(this.group)[this.group == 1]
      LOL[[s]][[paste0("G",g)]] = as.list(this.items)
        #
    }
  }
  LOL

}



proxima <- function(list_of_graphs, Labels = NULL, method = "jaccard", diag.value = NA) {
  
  if(method != "jaccard") stop("Currently, only Jaccard proximity scores are supported")
  LPM = NULL
  for (graph.name in names(list_of_graphs)){
    graph <- list_of_graphs[[graph.name]]
    if(method == "jaccard"){
      ## From a graph make an LDM with Jacard distance measures
      ## x.name changes the name of the column carrying the distnace measure
      # node names
      x.name="proximity"
      leaves.only = TRUE
      if(leaves.only){
        N <- leaves(graph, degree.dir="out")
      }else{
        N <- nodes(graph)
      }
      N <- sort(N)
      # list of ancestors per node
      # for optimization purposes, first the graph is reversed once
      rgraph <- reverseEdgeDirections(graph)
      # then retrieve the descendants
      A <- llply(N,descendants,rgraph)
      names(A)<-N
      # upper triangle combination of node(name)s
      AA <- cbind(t(combn(A,2)))
      NN <- cbind(t(combn(N,2)))
      # jaccard distance score, 
      # a constant of two is added to the divisor to distinguish proximity of the node to itself (the diagonale)
      # from proximity of two nodes in the same group
      Jacc <- function(c) (length(intersect(c[[1]],c[[2]]))-1)/ (length(union(c[[1]],c[[2]]))-1)
      # Dot it!
      J <- apply(AA,1,Jacc)
      this.LPM <- data.frame(ID = graph.name, i=NN[,1],j=NN[,2], proximity = J, stringsAsFactors=F)
      # colnames(this.LPM)<-c("i","j",x.name)
      if(is.null(LPM)) {
        LPM <- this.LPM
      } else {
        LPM <- rbind(LPM, this.LPM)
      }
    }
  }
  ## adding mirrored values
  LPM <- rbind(LPM, data.frame(ID = LPM$ID, i = LPM$j, j = LPM$i, proximity = LPM$proximity))
  ## adding diagonale
  diag <- expand.grid(ID = unique(LPM$ID), i = N) %>% 
    mutate(j = i, proximity = diag.value)
  LPM <- rbind(LPM, diag)
  
  ## Adding labels
  if(!is.null(Labels)){
    LPM <- LPM %>%
      mutate(i = as.character(i), j = as.character(j)) %>%
      left_join(dplyr::select(Labels, ID, label_i = label), by = c("i" = "ID")) %>%
      left_join(dplyr::select(Labels, ID, label_j = label), by = c("j" = "ID")) %>%
      mutate(i = label_i, j = label_j) %>%
      dplyr::select(-label_i, -label_j)
  }
  
  ## converting to factors
  LPM$ID <- as.factor(LPM$ID)
  LPM$i <- as.factor(LPM$i)
  LPM$j <- as.factor(LPM$j)
  
  return(LPM)
}


distima <- function(proxima,agg.func = mean, upper = 1){
  DM <- proxima %>%
    group_by(i,j) %>% 
    summarize_(proximity = ~agg.func(proximity)) %>%
    mutate(dissimilarity = upper - proximity) %>%  
    dcast(formula = j ~ i, value.var="dissimilarity") %>% 
    dplyr::select(-j) %>%
    as.matrix()
  rownames(DM) <- colnames(DM)
  DM
}

## Basic graph functions ####

rootNode<-function(graph) leaves(graph,degree.dir="in")

descendants <- function(node,graph){
  ## returns an ordered list of descendants nodes
  rev(names(acc(graph,node)[[1]]))
}

descendants_and_self <- function(node,graph){
  ## returns an ordered list of descendants nodes
  rev(c(node, names(acc(graph,node)[[1]])))
}

ancestors<-function(node,graph){
  ## returns an ordered list of ancestor nodes
  rgraph<-reverseEdgeDirections(graph)
  rev(names(acc(rgraph,node)[[1]]))
}

predecessor<-function(node, graph) ancestors(node,graph)[1]
father <- predecessor


siblings<-function(n,graph,self=F){
  ## returns an ordered list of sibling nodes  
  out<-adj(graph,ancestors(n,graph)[1])[[1]]
  if(self!=T) out<-out[out!=n]
  out
}

children<-function(n,graph, leavesonly=F){
  out <- adj(graph,n)[[1]]
  if(leavesonly) {
    out<-out[out %in% leaves(graph, degree.dir="out")]
  }
  out
}

leafGroups<-function(graph){
  unique(sapply(leaves(graph, degree.dir="out"), father, graph=graph))
}

commonAncestors<-function(a,b,graph)  intersect(ancestors(a,graph),ancestors(b,graph))


## returns the list of ancestors that two nodes have in common

## Heatmap ####
## https://cwcode.wordpress.com/2013/01/30/ggheatmap-version-2/
## 
## colours, generated by
## library(RColorBrewer)
## rev(brewer.pal(11,name="RdYlBu"))
my.colours <- c("#313695", "#4575B4", "#74ADD1", "#ABD9E9", "#E0F3F8", "#FFFFBF",
								"#FEE090", "#FDAE61", "#F46D43", "#D73027", "#A50026")

mydplot <- function(ddata, row=!col, col=!row, labels=col) {
	## plot a dendrogram
	yrange <- range(ddata$segments$y)
	yd <- yrange[2] - yrange[1]
	nc <- max(nchar(as.character(ddata$labels$label)))
	tangle <- if(row) { 0 } else { 90 }
	tshow <- col
	p <- ggplot() +
		geom_segment(data=segment(ddata), aes(x=x, y=y, xend=xend, yend=yend)) +
		labs(x = NULL, y = NULL) + theme_dendro()
	if(row) {
		p <- p +
			scale_x_continuous(expand=c(0.5/length(ddata$labels$x),0)) +
			coord_flip()
	} else {
		p <- p +
			theme(axis.text.x = element_text(angle = 90, hjust = 1))
	}
	return(p)
}

g_legend<-function(a.gplot){
	## from
	## http://stackoverflow.com/questions/11883844/inserting-a-table-under-the-legend-in-a-ggplot2-histogram
	tmp <- ggplot_gtable(ggplot_build(a.gplot))
	leg <- which(sapply(tmp$grobs, function(x) x$name) == "guide-box")
	legend <- tmp$grobs[[leg]]
	return(legend)
}
##' Display a ggheatmap
##'
##' this function sets up some viewports, and tries to plot the dendrograms to line up with the heatmap
##' @param L a list with 3 named plots: col, row, centre, generated by ggheatmap
##' @param col.width,row.width number between 0 and 1, fraction of the device devoted to the column or row-wise dendrogram. If 0, don't print the dendrogram
##' @return no return value, side effect of displaying plot in current device
##' @export
##' @author Chris Wallace
ggheatmap.show <- function(L, col.width=0.2, row.width=0.2) {
	grid.newpage()
	top.layout <- grid.layout(nrow = 2, ncol = 2,
														widths = unit(c(1-row.width,row.width), "null"),
														heights = unit(c(col.width,1-row.width), "null"))
	pushViewport(viewport(layout=top.layout))
	if(col.width>0)
		print(L$col, vp=viewport(layout.pos.col=1, layout.pos.row=1))
	if(row.width>0)
		print(L$row, vp=viewport(layout.pos.col=2, layout.pos.row=2))
	## print centre without legend
	print(L$centre +
					theme(axis.line=element_blank(),
								axis.text.x=element_blank(),axis.text.y=element_blank(),
								axis.ticks=element_blank(),
								axis.title.x=element_blank(),axis.title.y=element_blank(),
								legend.position="none",
								panel.background=element_blank(),
								panel.border=element_blank(),panel.grid.major=element_blank(),
								panel.grid.minor=element_blank(),plot.background=element_blank()),
				vp=viewport(layout.pos.col=1, layout.pos.row=2))
	## add legend
	legend <- g_legend(L$centre)
	pushViewport(viewport(layout.pos.col=2, layout.pos.row=1))
	grid.draw(legend)
	upViewport(0)
}
##' generate a heatmap + dendrograms, ggplot2 style
##'
##' @param x data matrix
##' @param hm.colours vector of colours (optional)
##' @return invisibly returns a list of ggplot2 objects. Display them with ggheatmap.show()
##' @author Chris Wallace
##' @export
##' @examples
##' ## test run
##' ## simulate data
##' library(mvtnorm)
##' sigma=matrix(0,10,10)
##' sigma[1:4,1:4] <- 0.6
##' sigma[6:10,6:10] <- 0.8
##' diag(sigma) <- 1
##' X <- rmvnorm(n=100,mean=rep(0,10),sigma=sigma)
##'  
##' ## make plot
##' p <- ggheatmap(X)
##'  
##' ## display plot
##' ggheatmap.show(p)
ggheatmap <- function(x,
											hm.colours=my.colours,
                      hc.method = "ward.D") {
	if(is.null(colnames(x)))
		colnames(x) <- sprintf("col%s",1:ncol(x))
	if(is.null(rownames(x)))
		rownames(x) <- sprintf("row%s",1:nrow(x))
	## plot a heatmap
	## x is an expression matrix
	row.hc <- hclust(dist(x), hc.method)
	col.hc <- hclust(dist(t(x)), hc.method)
	row.dendro <- dendro_data(as.dendrogram(row.hc),type="rectangle")
	col.dendro <- dendro_data(as.dendrogram(col.hc),type="rectangle")
	
	## dendro plots
	col.plot <- mydplot(col.dendro, col=TRUE, labels=TRUE) +
		scale_x_continuous(breaks = 1:ncol(x),labels=col.hc$labels[col.hc$order]) +
		theme(plot.margin = unit(c(0,0,0,0), "lines"))
	row.plot <- mydplot(row.dendro, row=TRUE, labels=FALSE) +
		theme(plot.margin = unit(rep(0, 4), "lines"))
	
	## order of the dendros
	col.ord <- match(col.dendro$labels$label, colnames(x))
	row.ord <- match(row.dendro$labels$label, rownames(x))
	xx <- x[row.ord,col.ord]
	dimnames(xx) <- NULL
	xx <- melt(xx)
	
	centre.plot <- ggplot(xx, aes(X2,X1)) + geom_tile(aes(fill=value), colour="white") +
		scale_fill_gradientn(colours = hm.colours) +
		labs(x = NULL, y = NULL) +
		scale_x_continuous(expand=c(0,0)) +
		scale_y_continuous(expand=c(0,0),breaks = NULL) +
		theme(plot.margin = unit(rep(0, 4), "lines"))
	ret <- list(col=col.plot,row=row.plot,centre=centre.plot)
	invisible(ret)
}