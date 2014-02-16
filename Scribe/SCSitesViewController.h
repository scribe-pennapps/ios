//
//  SCSitesViewController.h
//  Scribe
//
//  Created by Michael Scaria on 2/14/14.
//  Copyright (c) 2014 MichaelScaria. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol SCSitesViewControllerDelegate <NSObject>

- (void)goToCamera;

@end
@interface SCSitesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    NSArray *sites;
}

@property (nonatomic, strong) id <SCSitesViewControllerDelegate> delegate;
@property (strong, nonatomic) IBOutlet UITableView *tableView;

- (IBAction)goToCamera:(id)sender;
@end
