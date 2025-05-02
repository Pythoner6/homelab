{lib}: drv: if lib.attrsets.isDerivation drv then drv.name or drv.drvAttrs.name else throw "Expected derivation"
