//
//  BTBluetoothManager.m
//  bluetooth-demo
//
//  Created by John Bender on 9/26/13.
//  
//

#import "BTBluetoothManager.h"
#define kBTAppID @"bluetoofdemo"

static BTBluetoothManager *sharedInstance = nil;

@implementation BTBluetoothManager

+(BTBluetoothManager*) instance
{
    if( sharedInstance == nil )
        sharedInstance = [BTBluetoothManager new];
    return sharedInstance;
}

-(id) init
{
    self = [super init];
    if( self ) {
        // Capture the user-defined device name
        MCPeerID *myId = [[MCPeerID alloc] initWithDisplayName:[[UIDevice currentDevice] name]];
        
        // Search for a 15-character max appID
        nearbyBrowser = [[MCNearbyServiceBrowser alloc] initWithPeer:myId serviceType:kBTAppID];
        nearbyBrowser.delegate = self;
        [nearbyBrowser startBrowsingForPeers];

        // Advertise a 15-character max appID
        nearbyAdvertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:myId discoveryInfo:nil serviceType:kBTAppID];
        nearbyAdvertiser.delegate = self;
        [nearbyAdvertiser startAdvertisingPeer];

        session = [[MCSession alloc] initWithPeer:myId];
        session.delegate = self;
    }
    return self;
}


// Start receiving a resource from remote peer
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
}

// Received a byte stream from remote peer
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
}

// Finished receiving a resource from remote peer and saved the content in a temporary location - the app is responsible for moving the file to a permanent location within its sandbox
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
}


+(BOOL) hasConnection
{
    return (sharedInstance != nil && sharedInstance.peerName != nil);
}


// Take a dictionary passed from the BTBubbleView, encode it, and send it to session connected peers.
-(void) sendDictionaryToPeers:(NSDictionary*)dict
{
    NSError *error = nil;
    NSData *encodedData = [NSKeyedArchiver archivedDataWithRootObject:dict];
    [session sendData:encodedData toPeers:session.connectedPeers withMode:MCSessionSendDataReliable error:&error];
    
    if (error) {
        NSLog(@"Bluetooth connection error %@", error);
    }
}


#pragma mark - Nearby browser delegate

-(void) browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    [browser invitePeer:peerID toSession:session withContext:nil timeout:0];
}

-(void) browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
}


#pragma mark - Nearby advertiser delegate

-(void) advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession *))invitationHandler
{
    invitationHandler( YES, session );
}


#pragma mark - Session delegate

-(void) session:(MCSession*)theSession
           peer:(MCPeerID *)peerID
 didChangeState:(MCSessionState)state
{
    if( state == MCSessionStateConnected )
    {
        NSDictionary *handshake = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @(BluetoothCommandHandshake), @"command",
                                   [[UIDevice currentDevice] name], @"peerName",
                                   nil];
        [self sendDictionaryToPeers:handshake];
    }
    else if( state == MCSessionStateNotConnected )
    {
    }
}


- (void)session:(MCSession *)session
 didReceiveData:(NSData *)data
       fromPeer:(MCPeerID *)peerID
{
    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    
    // Log dict??
    NSLog(@"Dict: %@", dict);

    NSInteger command = [dict[@"command"] intValue];

    switch( command )
    {
        case BluetoothCommandHandshake:
        {
            _peerName = [dict objectForKey:@"peerName"];

            // start negotiating player index
            playerIndexTimestamp = [NSDate date];
            
            //Log player timestamp (that's you)
            //NSLog(@"Log of player timestamp %d", playerIndexTimestamp);
            NSDictionary *negotiation = @{@"command":     @(BluetoothCommandNegotiate),
                                          @"playerIndex": @0,
                                          @"timestamp":   playerIndexTimestamp};
            
            // Logging negotiation
            NSLog(@"Negotiation for playerIndexTimestamp: %@", negotiation);
            
            [self sendDictionaryToPeers:negotiation];
            break;
        }
        case BluetoothCommandNegotiate:
        {
            NSDate *otherTimestamp = [dict objectForKey:@"timestamp"];
            // Log otherTimestamp
            NSLog(@"Log of other player timestamp %@", otherTimestamp);
            NSInteger otherPlayer = [[dict objectForKey:@"playerIndex"] intValue];
            // Log other player index
            NSLog(@"Log of other player index %ld", (long)otherPlayer);

            if( [otherTimestamp compare:playerIndexTimestamp] == NSOrderedAscending )
            {
                // other timestamp was earlier, so it wins
                _playerIndex = 1 - otherPlayer;
                NSDictionary *negotiation = [NSDictionary dictionaryWithObjectsAndKeys:
                                             [NSNumber numberWithInt:BluetoothCommandNegotiateConfirm], @"command",
                                             [NSNumber numberWithInt:_playerIndex], @"playerIndex",
                                             nil];
                NSLog(@"Another log of the negotiation %@", negotiation);
                [self sendDictionaryToPeers:negotiation];

                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Set Player Index"
                                                                    message:[NSString stringWithFormat:@"Other timestamp won, setting my index to %li", (long)_playerIndex]
                                                                   delegate:nil
                                                          cancelButtonTitle:@"OK"
                                                          otherButtonTitles:nil];
                    [alert show];
                });
            }
            break;
        }
        case BluetoothCommandNegotiateConfirm:
        {
            NSInteger otherPlayer = [[dict objectForKey:@"playerIndex"] intValue];
            _playerIndex = 1 - otherPlayer;

            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Set Player Index"
                                                                message:[NSString stringWithFormat:@"Peer confirmed my timestamp won, setting my index to %li", (long)_playerIndex]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
                [alert show];
            });

            break;
        }
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"bluetoothDataReceived" object:dict];
}


@end
