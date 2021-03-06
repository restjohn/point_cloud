//
//  LAZReader.m
//  LidarViewer
//
//  Created by Steve Gifford on 10/27/15.
//  Copyright © 2015 mousebird consulting. All rights reserved.
//

#import "LAZReader.h"
#include <fstream>
#include <iostream>

@implementation LAZReader
{
    NSArray *pointObjs;
}

- (id)init
{
    self = [super init];
    _maxPoints = 3000000;
    _skipPoints = 6;
    
    return self;
}

- (void)readPoints:(NSString *)fileName viewC:(MaplyBaseViewController *)viewC
{
    std::ifstream ifs;
    ifs.open([fileName cStringUsingEncoding:NSASCIIStringEncoding], std::ios::in | std::ios::binary);
    
    //    std::string wktSRS = "NAD83 / UTM zone 10N|NAD83|";
//    OGRSpatialReference inSRS("PROJCS[\"NAD83 / UTM zone 10N\",GEOGCS[\"NAD83\",DATUM[\"North_American_Datum_1983\",SPHEROID[\"GRS 1980\",6378137,298.257222101,AUTHORITY[\"EPSG\",\"7019\"]],TOWGS84[0,0,0,0,0,0,0],AUTHORITY[\"EPSG\",\"6269\"]],PRIMEM[\"Greenwich\",0,AUTHORITY[\"EPSG\",\"8901\"]],UNIT[\"degree\",0.0174532925199433,AUTHORITY[\"EPSG\",\"9122\"]],AUTHORITY[\"EPSG\",\"4269\"]],PROJECTION[\"Transverse_Mercator\"],PARAMETER[\"latitude_of_origin\",0],PARAMETER[\"central_meridian\",-123],PARAMETER[\"scale_factor\",0.9996],PARAMETER[\"false_easting\",500000],PARAMETER[\"false_northing\",0],UNIT[\"metre\",1,AUTHORITY[\"EPSG\",\"9001\"]],AXIS[\"Easting\",EAST],AXIS[\"Northing\",NORTH],AUTHORITY[\"EPSG\",\"26910\"]]");
    //    inSRS.importFromProj4("+proj=utm +zone=10 +ellps=GRS80 +datum=NAD83 +units=m +no_defs");
//    OGRSpatialReference outSRS;
//    outSRS.importFromProj4("+proj=geocent +datum=WGS84");
//    OGRCoordinateTransformation *trans = OGRCreateCoordinateTransformation(&inSRS,&outSRS);
    
    liblas::ReaderFactory f;
    liblas::Reader reader = f.CreateWithStream(ifs);
    liblas::Header header = reader.GetHeader();
    liblas::SpatialReference srs = header.GetSRS();
    std::string proj4Str = srs.GetProj4();
    
    //    double scaleX = header.GetScaleX();
    //    double scaleY = header.GetScaleY();
    //    double scaleZ = header.GetScaleZ();
    double scaleX = 1.0, scaleY = 1.0, scaleZ = 1.0;

    if (proj4Str.empty())
    {
        // Note: Make up a coordinate system
    }

    MaplyProj4CoordSystem *inSys = [[MaplyProj4CoordSystem alloc] initWithString:[NSString stringWithFormat:@"%s",proj4Str.c_str()]];
    
    // Figure out the bounds
    liblas::Bounds<double> bounds = header.GetExtent();
    double midX = (bounds.minx() + bounds.maxx())/2.0;
    double midY = (bounds.miny() + bounds.maxy())/2.0;
    
    // Figure out where the middle is and go there
    dispatch_async(dispatch_get_main_queue(),
                   ^{
                       if ([viewC isKindOfClass:[WhirlyGlobeViewController class]])
                       {
                           WhirlyGlobeViewController *globeVC = (WhirlyGlobeViewController *)viewC;
                           MaplyCoordinate coord = [inSys localToGeo:MaplyCoordinateMake(midX, midY)];
                           [globeVC animateToPosition:coord time:1.0];
                       }
                   });

    int allocPoints = 50000 * _skipPoints;
    int allPoints = 0;
    int displayedPoints = 0;
    
    bool hasColors = header.GetDataFormatId() != liblas::ePointFormat0 && header.GetDataFormatId() != liblas::ePointFormat1;
    
    bool done = false;
    NSMutableArray *pointsObjMut = [NSMutableArray array];
    while (!done)
    {
        @autoreleasepool
        {
            int numPoints = 0;
            
            MaplyPoints *points = [[MaplyPoints alloc] initWithNumPoints:(allocPoints/_skipPoints)];
            while (reader.ReadNextPoint() && numPoints < allocPoints)
            {
                // Get the point and convert to geocentric
                liblas::Point const& p = reader.GetPoint();
//                double x,y,z;
//                x = p.GetX(), y = p.GetY(); z = p.GetZ();
//                trans->TransformEx(1, &x, &y, &z);
                MaplyCoordinate3dD coord;
                coord.x = p.GetX();  coord.y = p.GetY();  coord.z = p.GetZ();
                MaplyCoordinate3dD geoc = [inSys localToGeocentric:coord];
                
                geoc.x *= scaleX;  geoc.y *= scaleY;  geoc.z *= scaleZ;
                
                // Scale that to our fake display coordinates
                geoc.x /= 6371000; geoc.y /= 6371000; geoc.z /= 6371000;
                
                // Note: Nudging above the datum
                geoc.x *= 1.0005;  geoc.y *= 1.0005;  geoc.z *= 1.0005;
                
                if (numPoints % _skipPoints == 0) {
                    float red = 1.0,green = 1.0, blue = 1.0;
                    if (hasColors)
                    {
                        liblas::Color color = p.GetColor();
                        red = color.GetRed() / 255.0;  green = color.GetGreen() / 255.0;  blue = color.GetBlue() / 255.0;
                    }
                    [points addDispCoordDoubleX:geoc.x y:geoc.y z:geoc.z];
                    [points addColorR:red g:green b:blue a:1.0];
                    displayedPoints++;
                }
                
                numPoints++;
                allPoints++;
            }
            
            if (numPoints < allocPoints)
                done = true;
            
            if (numPoints > 0)
            {
                MaplyComponentObject *compObj = [viewC addPoints:@[points] desc:
                                                 @{kMaplyColor: [UIColor redColor],
                                                   kMaplyPointSize: @(6.0),
                                                   kMaplyDrawPriority: @(10000000),
                                                   kMaplyShader: _shader.name,
                                                   kMaplyZBufferRead: @(YES),
                                                   kMaplyZBufferWrite: @(YES)
                                                   }
                                                                 mode:MaplyThreadAny];
                if (compObj)
                    [pointsObjMut addObject:compObj];
            }
            
            if (displayedPoints > _maxPoints)
            {
                done = true;
            }
        }
    }
    
    pointObjs = pointsObjMut;
    
    NSLog(@"Displaying a total of %d points",displayedPoints);
}

@end
