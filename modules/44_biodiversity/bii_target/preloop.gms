*** |  (C) 2008-2021 Potsdam Institute for Climate Impact Research (PIK)
*** |  authors, and contributors see CITATION.cff file. This file is part
*** |  of MAgPIE and licensed under AGPL-3.0-or-later. Under Section 7 of
*** |  AGPL-3.0, you are granted additional permissions described in the
*** |  MAgPIE License Exception, version 1.0 (see LICENSE file).
*** |  Contact: magpie@pik-potsdam.de

v44_bii.l(biome44) = 0.75;

v44_bii.fx(biome44)$(sum(j, f44_biome(j,biome44)) = 0) = 0;
v44_bii_missing.fx(biome44)$(sum(j, f44_biome(j,biome44)) = 0) = 0;
p44_bii_lower_bound(t,biome44) = 0;

vm_bv.l(j,landcover44,potnatveg) = 0;
