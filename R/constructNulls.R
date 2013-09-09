.zeroInMeth <- function(aD, smallSegs)
  {
    zeroCs <- !getOverlaps(aD@alignments, smallSegs, whichOverlaps = FALSE)
#    zeroCs <- rowSums(sapply(1:ncol(aD), function(ii) as.integer(aD@Cs[,ii]))) == 0
    
    chrBreaks <- which(seqnames(aD@alignments)[-nrow(aD)] != seqnames(aD@alignments)[-1])
    chrBreaks <- cbind(c(1, chrBreaks + 1), c(chrBreaks, nrow(aD)))
    
    whichZero <- which(zeroCs)

    if(length(whichZero) > 0) {
      zeroBlocks <- do.call("rbind", lapply(1:nrow(chrBreaks), function(ii) {
        chrZeros <- whichZero[whichZero >= chrBreaks[ii,1] & whichZero <= chrBreaks[ii,2]]      
        adjZeros <- cbind(chrZeros[c(1, which(diff(chrZeros) > 1) + 1)], chrZeros[c(which(diff(chrZeros) > 1), length(chrZeros))])
      }))
      
      zeroCoords <- GRanges(seqnames(aD@alignments)[zeroBlocks[,1]], IRanges(start = start(aD@alignments)[zeroBlocks[,1]], end = end(aD@alignments)[zeroBlocks[,2]]))
    } else {
      zeroCoords <- GRanges()
      seqinfo(zeroCoords) <- seqinfo(aD@alignments)
    }
      
    zeroCoords
  }      


.constructMethNulls <- function(emptyNulls, sDWithin, locDef)
  {
    leftRight <- do.call("rbind", lapply(seqlevels(sDWithin@coordinates), function(chr) {
      leftids <- findInterval(start(sDWithin@coordinates[seqnames(sDWithin@coordinates) == chr,]), end(emptyNulls[seqnames(emptyNulls) == chr,]))
      leftids[leftids <= 0] <- NA      
      left <- start(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]) - start(emptyNulls[seqnames(emptyNulls) == chr])[leftids]

      rightids <- findInterval(end(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr)]), end(emptyNulls[seqnames(emptyNulls) == chr,])) + 1
      rightids[rightids > sum(seqnames(emptyNulls) == chr)] <- NA
      right = end(emptyNulls[seqnames(emptyNulls) == chr])[rightids] - end(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),])
      
      cbind(left, right)
    }))

    emptyInside <- which(getOverlaps(emptyNulls, sDWithin@coordinates, overlapType = "within", whichOverlaps = FALSE, cl = NULL))
    
    emptyData <- do.call("cbind", lapply(1:ncol(sDWithin), function(ii) rep(0L, length(emptyNulls))))

    leftGood <- (!is.na(leftRight[,'left']))
    rightGood <- (!is.na(leftRight[,'right']))
    
    nullCoords = GRanges(
      seqnames = c(seqnames(emptyNulls), seqnames(sDWithin@coordinates)[c(which(leftGood & rightGood), which(leftGood), which(rightGood))]),
      IRanges(
              start = c(start(emptyNulls),
                (start(sDWithin@coordinates) - leftRight[,"left"])[leftGood & rightGood],
                (start(sDWithin@coordinates) - leftRight[,"left"])[leftGood],
                (start(sDWithin@coordinates))[rightGood]),
              end = c(end(emptyNulls),
                (end(sDWithin@coordinates) + leftRight[,"right"])[leftGood & rightGood],
                (end(sDWithin@coordinates))[leftGood],
                (end(sDWithin@coordinates) + leftRight[,'right'])[rightGood]))
              )
    
    rordNull <- order(as.integer(seqnames(nullCoords)), start(nullCoords), end(nullCoords))
    unqNull <- .fastUniques(cbind(as.integer(seqnames(nullCoords)), start(nullCoords), end(nullCoords))[rordNull,])
    nullCoords <- nullCoords[rordNull,][unqNull,]
    
    overLoci <- which(getOverlaps(coordinates = nullCoords, segments = locDef, overlapType = "within", whichOverlaps = FALSE, cl = NULL))
    nullCoords <- nullCoords[overLoci,]

    potnullD <- new("segMeth",
                    replicates = sDWithin@replicates,
                    coordinates = nullCoords)    
    potnullD
  }

.constructNulls <- function(emptyNulls, sDWithin, locDef, forPriors = FALSE, samplesize, aD = aD)
  {
    # find the gap to the left and right of each element of sD within a locus (sDWithin)
    leftRight <- matrix(NA, ncol = 2, nrow = nrow(sDWithin))
    colnames(leftRight) <- c("left", "right")

    for(ss in levels(strand(sDWithin@coordinates)))      
      leftRight[which(strand(sDWithin@coordinates) == ss),] <- do.call("rbind", lapply(seqlevels(sDWithin@coordinates), function(chr) {
        sDsel <- which(seqnames(sDWithin@coordinates) == chr & strand(sDWithin@coordinates) == ss)
        empsel <- which(seqnames(emptyNulls) == chr & strand(emptyNulls) == ss)
        left <- start(sDWithin@coordinates[sDsel,]) -
          start(emptyNulls[empsel])[match(start(sDWithin@coordinates[sDsel,]), (end(emptyNulls[empsel,]) + 1))]
        right <- end(emptyNulls[empsel])[match(end(sDWithin@coordinates[sDsel,]), (start(emptyNulls[empsel,]) - 1))] - end(sDWithin@coordinates[sDsel,])
        cbind(left, right)
      }))
      

    # select from the empty regions those within or adjacent (unless looking to construct priors) to a potential locus
    
    empties <- which(getOverlaps(emptyNulls, sDWithin@coordinates, overlapType = "within", whichOverlaps = FALSE, cl = NULL))

    if(!forPriors) empties <- union(empties,
                                    unlist(lapply(levels(seqnames(sDWithin@coordinates)), function(chr) {
                                      leftEmpties <- match(start(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]), (end(emptyNulls[seqnames(emptyNulls) == chr,]) + 1))
                                      rightEmpties <- match(end(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]), (start(emptyNulls[seqnames(emptyNulls) == chr,]) - 1))
                                      which(seqnames(emptyNulls) == chr)[union(leftEmpties, rightEmpties)]
                       }))
                                    )    
    empties <- empties[!is.na(empties)]

    leftGood <- (!is.na(leftRight[,'left']))
    rightGood <- (!is.na(leftRight[,'right']))

    # combine regions with gaps to the left, gaps to the right, gaps on both side, plus empty regions within loci
    
    nullCoords = GRanges(
      seqnames = c(
        seqnames(emptyNulls[empties,]),
        seqnames(sDWithin@coordinates)[c(which(leftGood & rightGood), which(leftGood), which(rightGood))]),
      IRanges(
              start = c(start(emptyNulls[empties,]),
                (start(sDWithin@coordinates) - leftRight[,"left"])[which(leftGood & rightGood)],
                (start(sDWithin@coordinates) - leftRight[,"left"])[which(leftGood)],
                (start(sDWithin@coordinates))[which(rightGood)]),
              end = c(end(emptyNulls[empties,]),
                (end(sDWithin@coordinates) + leftRight[,"right"])[which(leftGood & rightGood)],
                (end(sDWithin@coordinates))[which(leftGood)],
                (end(sDWithin@coordinates) + leftRight[,'right'])[which(rightGood)])),
      sDID = c(rep(-1, length(empties)), which(leftGood & rightGood), which(leftGood), which(rightGood)),
      strand = c(
        strand(emptyNulls[empties,]),
        strand(sDWithin@coordinates)[c(which(leftGood & rightGood), which(leftGood), which(rightGood))])
      )
      

    # which constructed coordinates lie within a locus?    
    nullCoords <- nullCoords[which(getOverlaps(coordinates = nullCoords, segments = locDef, overlapType = "within", whichOverlaps = FALSE, cl = NULL)),]

    if(forPriors) {
      nullCoords <- nullCoords[.filterSegments(nullCoords, runif(length(nullCoords)), maxReport = samplesize),]
    }
                                        # empty regions carry no data    
    
    if(class(sDWithin) == "segData") {
      nullData <- matrix(0L, nrow = length(nullCoords), ncol = ncol(sDWithin))
      colnames(nullData) <- colnames(sDWithin@data)
      nullData[nullCoords$sDID > 0,] <- sDWithin@data[nullCoords$sDID[nullCoords$sDID > 0],]
      values(nullCoords) <- NULL
      potnullD <- new("segData", data = nullData,
                      libsizes = sDWithin@libsizes,
                      replicates = sDWithin@replicates,
                      coordinates = nullCoords)
    } else if(class(sDWithin) == "segMeth") {
      values(nullCoords) <- NULL
      potnullD <- new("segMeth",
                      Cs = matrix(NA, ncol = ncol(sDWithin), nrow = length(nullCoords)),
                      Ts = matrix(NA, ncol = ncol(sDWithin), nrow = length(nullCoords)),        
                      replicates = sDWithin@replicates,
                      coordinates = nullCoords)      
      nullCounts <- getCounts(potnullD@coordinates, aD, cl = cl)
      potnullD@Cs <- nullCounts$Cs
      potnullD@Ts <- nullCounts$Ts
      potnullD <- potnullD[rowSums(potnullD@Cs) + rowSums(potnullD@Ts) > 0,]
    }
      
    potnullD
  }


.constructNullPriors <- function(emptyNulls, sDWithin, locDef, samplesize)
  {
    
    leftRight <- do.call("rbind", lapply(seqlevels(sDWithin@coordinates), function(chr) {
      left <- start(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]) -
        start(emptyNulls[seqnames(emptyNulls) == chr])[match(start(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]), (end(emptyNulls[seqnames(emptyNulls) == chr,]) + 1))]
      right <- end(emptyNulls[seqnames(emptyNulls) == chr])[match(end(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),]), (start(emptyNulls[seqnames(emptyNulls) == chr,]) - 1))] - end(sDWithin@coordinates[which(seqnames(sDWithin@coordinates) == chr),])
      cbind(left, right)
    }))

    empover <- getOverlaps(emptyNulls, sDWithin@coordinates, overlapType = "within", whichOverlaps = FALSE, cl = NULL)
    if(any(empover)) emptyNulls <- emptyNulls[which(empover),] else emptyNulls <- emptyNulls[FALSE,]
    
    leftGood <- !is.na(leftRight[,'left'])
    rightGood <- !is.na(leftRight[,'right'])    
    
    nullCoords <- GRanges(
      seqnames = c(
        seqnames(emptyNulls),
        seqnames(sDWithin@coordinates)[leftGood & rightGood],
        seqnames(sDWithin@coordinates)[leftGood],
        seqnames(sDWithin@coordinates)[rightGood]),
                    IRanges(
                      start = c(
                        start(emptyNulls),
                        (start(sDWithin@coordinates) - leftRight[,"left"])[leftGood & rightGood],
                        (start(sDWithin@coordinates) - leftRight[,"left"])[leftGood],
                        (start(sDWithin@coordinates))[rightGood]),              
                      end = c(end(emptyNulls),
                        (end(sDWithin@coordinates) + leftRight[,"right"])[leftGood & rightGood],
                        (end(sDWithin@coordinates))[leftGood],
                        (end(sDWithin@coordinates) + leftRight[,'right'])[rightGood])
                      ))
    
    overLoci <- which(getOverlaps(coordinates = nullCoords, segments = locDef, overlapType = "within", whichOverlaps = FALSE, cl = NULL))        
    filNulls <- sort(overLoci[.filterSegments(nullCoords[overLoci], runif(length(overLoci)), maxReport = samplesize)])
    splitNulls <- c(length(emptyNulls), sum(leftGood & rightGood), sum(leftGood), sum(rightGood))
    emptyData <- do.call("cbind", lapply(1:ncol(sDWithin), function(x) (rep(0L, sum(filNulls <= splitNulls[1])))))    

    lrChoose <- which(leftGood & rightGood)[filNulls[filNulls > cumsum(splitNulls)[1] & filNulls <= cumsum(splitNulls)[2]] - cumsum(splitNulls)[1]]
    leftChoose <- which(leftGood)[filNulls[filNulls > cumsum(splitNulls)[2] & filNulls <= cumsum(splitNulls)[3]] - cumsum(splitNulls)[2]]
    rightChoose <- which(rightGood)[filNulls[filNulls > cumsum(splitNulls)[3] & filNulls <= cumsum(splitNulls)[4]] - cumsum(splitNulls)[3]]
    
    if(class(sDWithin) == "segData") {
      colnames(emptyData) <- colnames(sDWithin@data)
      potnullD <- new("segData", data = rbind(emptyData, sDWithin@data[c(lrChoose, leftChoose, rightChoose),]),
                      libsizes = sDWithin@libsizes,
                      replicates = sDWithin@replicates,
                      coordinates = nullCoords[filNulls])
    } else if(class(sDWithin) == "segMeth") {
      colnames(emptyData) <- colnames(sDWithin@Cs)
      potnullD <- new("segMeth",
                      Cs = rbind(emptyData, sDWithin@Cs[c(lrChoose, leftChoose, rightChoose),]),
                      Ts = rbind(emptyData, sDWithin@Ts[c(lrChoose, leftChoose, rightChoose),]),
                      replicates = sDWithin@replicates,
                      coordinates = nullCoords[filNulls])
    }
    
    potnullD <- potnullD[order(as.integer(seqnames(potnullD@coordinates)), start(potnullD@coordinates), end(potnullD@coordinates)),]
    
    potnullD
  }