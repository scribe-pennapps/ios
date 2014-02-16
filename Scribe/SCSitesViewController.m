//
//  SCSitesViewController.m
//  Scribe
//
//  Created by Michael Scaria on 2/14/14.
//  Copyright (c) 2014 MichaelScaria. All rights reserved.
//

#import "SCSitesViewController.h"

@interface SCSitesViewController ()

@end

@implementation SCSitesViewController

- (IBAction)goToCamera:(id)sender {
    [_delegate goToCamera];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    sites = [[NSUserDefaults standardUserDefaults] objectForKey:@"Sites"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"UpdatedLocations" object:nil];
}

- (void)refresh {
    sites = [[NSUserDefaults standardUserDefaults] objectForKey:@"Sites"];
    [_tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return sites.count;
}
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    }
//    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSDictionary *d = sites[indexPath.row];
    UILabel *title = (UILabel *)[cell viewWithTag:1];
    title.text = d[@"Title"];
    UILabel *url = (UILabel *)[cell viewWithTag:2];
    url.text = d[@"URL"];
    return cell;
}


#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *d = sites[indexPath.row];
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, .5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@", d[@"URL"]]]];
//    });
}
@end
