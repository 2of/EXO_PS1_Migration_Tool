# Target naming configuration
# Example values only

$TargetNamingConfig = [PSCustomObject]@{

    Prefixes = @(
        "dl"
        "grp"
        "dg"
    )

    RegionMap = @{
        "NorthRegion"   = "NR"
        "SouthRegion"   = "SR"
        "EastRegion"    = "ER"
        "WestRegion"    = "WR"
        "CentralRegion" = "CR"
    }

    DomainRegionMap = @{
        "north.example.com"   = "NR"
        "south.example.com"   = "SR"
        "east.example.com"    = "ER"
        "west.example.com"    = "WR"
        "central.example.com" = "CR"
    }

    TargetDomain = "newdomain.example.com"

    UnknownRegionCode = "UNKNOWN"
}