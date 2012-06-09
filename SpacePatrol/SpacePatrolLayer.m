/* Copyright (c) 2012 Scott Lembcke and Howling Moon Software
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import <CoreMotion/CoreMotion.h>

#import "SpacePatrolLayer.h"
#import "ChipmunkAutoGeometry.h"
#import "ChipmunkDebugNode.h"

#import "DeformableTerrainSprite.h"
#import "SpaceBuggy.h"

#import "Physics.h"

#define PIXEL_SIZE 4.0
#define TILE_SIZE 32.0

static const ccColor4B SKY_COLOR = {30, 66, 78, 255};


enum Z_ORDER {
	Z_WORLD,
	Z_TERRAIN,
	Z_BUGGY,
	Z_EFFECTS,
	Z_DEBUG,
	Z_MENU,
};


#define WeakSelf(__var__) __unsafe_unretained typeof(*self) *__var__ = self


@interface SpacePatrolLayer()

@end


@implementation SpacePatrolLayer {
	CMMotionManager *motionManager;
	ChipmunkSpace *space;
	ChipmunkMultiGrab *multiGrab;
	ChipmunkDebugNode *debugNode;
	
	CCNode *world;
	DeformableTerrainSprite *terrain;
	
	UITouch *currentTouch;
	BOOL currentTouchRemoves;
	CGPoint lastTouchLocation;
	
	SpaceBuggy *buggy;
	
	ccTime _accumulator, _fixedTime;
}

+(CCScene *)scene
{
	CCScene *scene = [CCScene node];
	[scene addChild: [self node]];
	
	return scene;
}

-(id)init
{
	if((self = [super init])){
		world = [CCNode node];
		[self addChild:world z:Z_WORLD];
		
		// Setup the space
		space = [[ChipmunkSpace alloc] init];
		space.gravity = cpv(0.0f, -GRAVITY);
		
		multiGrab = [[ChipmunkMultiGrab alloc] initForSpace:space withSmoothing:cpfpow(0.8, 60) withGrabForce:1e4];
		multiGrab.grabRadius = 50.0;
//		multiGrab.pushMode = TRUE;
//		multiGrab.pushMass = 10.0;
//		multiGrab.pushFriction = 0.7;
//		multiGrab.layers = COLLISION_RULE_BUGGY_ONLY;
		
		terrain = [[DeformableTerrainSprite alloc] initWithSpace:space texelScale:32.0 tileSize:32];
		[world addChild:terrain z:Z_TERRAIN];
		
		buggy = [[SpaceBuggy alloc] initWithPosition:cpv(100.0, terrain.sampler.height*terrain.texelSize/3.0)];
		[world addChild:buggy.node z:Z_BUGGY];
		[space add:buggy];
		
		// Add a ChipmunkDebugNode to draw the space.
		debugNode = [ChipmunkDebugNode debugNodeForChipmunkSpace:space];
		[world addChild:debugNode z:Z_DEBUG];
		debugNode.visible = TRUE;
		
		// Show some menu buttons.
		CCMenuItemLabel *reset = [CCMenuItemLabel itemWithLabel:[CCLabelTTF labelWithString:@"Reset" fontName:@"Helvetica" fontSize:20] block:^(id sender){
			[[CCDirector sharedDirector] replaceScene:[[SpacePatrolLayer class] scene]];
		}];
		reset.position = ccp(50, 300);
		
		CCMenuItemLabel *showDebug = [CCMenuItemLabel itemWithLabel:[CCLabelTTF labelWithString:@"Show Debug" fontName:@"Helvetica" fontSize:20] block:^(id sender){
			debugNode.visible ^= TRUE;
		}];
		showDebug.position = ccp(400, 300);
		
		CCMenu *menu = [CCMenu menuWithItems:reset, showDebug, nil];
		menu.position = CGPointZero;
		[self addChild:menu z:Z_MENU];
		
		self.isTouchEnabled = TRUE;
	}
	
	return self;
}

-(void)onEnter
{
	motionManager = [[CMMotionManager alloc] init];
	motionManager.accelerometerUpdateInterval = [CCDirector sharedDirector].animationInterval;
	[motionManager startAccelerometerUpdates];
	
	[self scheduleUpdate];
	[super onEnter];
}

-(void)onExit
{
	[motionManager stopAccelerometerUpdates];
	motionManager = nil;
	
	[super onExit];
}

static cpBB
cpBBFromCGRect(CGRect rect)
{
	return cpBBNew(CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetMaxX(rect), CGRectGetMaxY(rect));
}

-(void)tick:(ccTime)fixed_dt
{
	[space step:fixed_dt];
}

-(void)updateGravity
{
#if TARGET_IPHONE_SIMULATOR
	CMAcceleration gravity = {-1, 0, 0};
#else
	CMAcceleration gravity = motionManager.accelerometerData.acceleration;
#endif
	
	space.gravity = cpvmult(cpv(-gravity.y, gravity.x), GRAVITY);
}

-(CGPoint)touchLocation:(UITouch *)touch
{
	return [terrain convertTouchToNodeSpace:currentTouch];
}

-(void)modifyTerrain
{
	CGFloat radius = 100.0;
	CGFloat threshold = 0.05*radius;
	
	CGPoint location = [self touchLocation:currentTouch];
	
	if(
		ccpDistanceSQ(location, lastTouchLocation) > threshold*threshold &&
		(currentTouchRemoves || ![space nearestPointQueryNearest:location maxDistance:0.75*radius layers:COLLISION_RULE_BUGGY_ONLY group:nil].shape)
	){
//		if(!currentTouchRemoves){
//			ChipmunkNearestPointQueryInfo *info = [space nearestPointQueryNearest:location maxDistance:radius layers:COLLISION_RULE_BUGGY_ONLY group:nil];
//			if(info.shape){
//				location = cpvadd(info.point, cpvmult(cpvnormalize(cpvsub(location, info.point)), radius));
//			}
//		}
		
		[terrain modifyTerrainAt:location radius:radius remove:currentTouchRemoves];
		lastTouchLocation = location;
	}
}

-(void)update:(ccTime)dt
{
	if(currentTouch) [self modifyTerrain];
	
	CGAffineTransform trans = CGAffineTransformInvert([terrain nodeToWorldTransform]);
	CGRect screen = CGRectMake(-100, -100, 680, 520);
	CGRect rect = CGRectApplyAffineTransform(screen, trans);
	
//	NSLog(@"rect: %@", NSStringFromCGRect(rect));
//	[debugNode drawSegmentFrom:rect.origin to:cpvadd(rect.origin, cpv(rect.size.width, rect.size.height)) radius:2.0 color:ccc4f(1, 0, 0, 1)];
	
	[terrain.tiles ensureRect:cpBBFromCGRect(rect)];
	
	[self updateGravity];
	
	// Update the physics
	ccTime fixed_dt = 1.0/240.0;
	
	_accumulator += dt;
	while(_accumulator > fixed_dt){
		[self tick:fixed_dt];
		_accumulator -= fixed_dt;
		_fixedTime += fixed_dt;
	}
	
	if(multiGrab.grabCount == 0){
		// TODO Should smooth this out better.
		world.position = cpvsub(cpv(240, 160), buggy.pos);
	}
}

-(void)scheduleBlockOnce:(void (^)(void))block delay:(ccTime)delay
{
	// There really needs to be a 
	[self.scheduler scheduleSelector:@selector(invoke) forTarget:[block copy] interval:0.0 paused:FALSE repeat:1 delay:delay];
}

//-(void)ccTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
//{
//	for(UITouch *touch in touches){
//		if(!currentTouch){
//			currentTouch = touch;
//			
//			cpFloat density = [terrain.sampler sample:[self touchLocation:currentTouch]];
//			currentTouchRemoves = (density < 0.5);
//		}
//	}
//}
//
//-(void)ccTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
//{
//	for(UITouch *touch in touches){
//		if(touch == currentTouch){
//			currentTouch = nil;
//		}
//	}
//}
//
//-(void)ccTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
//{
//	[self ccTouchesEnded:touches withEvent:event];
//}

-(void)ccTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	for(UITouch *touch in touches){
		[multiGrab beginLocation:[terrain convertTouchToNodeSpace:touch]];
		NSLog(@"multiGrabBegin %p", touch);
		
		if(!currentTouch){
			NSLog(@"deformTouchBegin %p", touch);
			currentTouch = touch;
			
			cpFloat density = [terrain.sampler sample:[self touchLocation:currentTouch]];
			currentTouchRemoves = (density < 0.5);
		}
	}
}

-(void)ccTouchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	for(UITouch *touch in touches){
		[multiGrab updateLocation:[terrain convertTouchToNodeSpace:touch]];
	}
}

-(void)ccTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	for(UITouch *touch in touches){
		NSLog(@"multiGrabEnd %p", touch);
		[multiGrab endLocation:[terrain convertTouchToNodeSpace:touch]];
		
		if(touch == currentTouch){
			NSLog(@"deformTouchEnd %p", touch);
			currentTouch = nil;
		}
	}
}

-(void)ccTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	[self ccTouchesEnded:touches withEvent:event];
}

@end
