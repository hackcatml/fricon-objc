#import "NSString+ShellExec.h"

#include <stdlib.h>
#include <unistd.h>
#include <spawn.h>
#include <Foundation/Foundation.h>

#define fridaplistPath @"/Library/LaunchDaemons/re.frida.server.plist"

NSString *shellCommand(NSString *shellcommand){
	NSString *output = [shellcommand runAsCommand];
	return output;
}

// check if frida-server is running
static BOOL isProcessRunning(NSString *processName) {
    BOOL running = NO;

    NSString *input = [NSString stringWithFormat:@"ps ax | grep '%@' | grep -v grep | wc -l", processName];
	NSString *output = [input runAsCommand];

    int val = (int)[output integerValue];
    if (val != 0) {
        running = YES;
    }

    return running;
}

void fridaStop(){
	printf("frida-server stopped.\n\n%s", [shellCommand(@"launchctl unload /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null") UTF8String]);
	// if still frida-server is running. kill it
	while(isProcessRunning(@"frida-server")){
		int pid = [shellCommand(@"ps ax | grep 'frida-server' | grep -v grep | cut -d' ' -f 2") intValue];
		NSString* input = [NSString stringWithFormat:@"kill -9 %d", pid];
		printf("%s\n", [shellCommand(input) UTF8String]);
	}
}

void checkWeirdFridaProcess(BOOL withArgs, NSString* op1, NSString* op2){
	// on iOS 15 sometimes weird process when start frida-server
	if(isProcessRunning(@"xpcproxy re.frida.server")){
		printf("weird xpcproxy re.frida.server process. restart...\n");
		fridaStop();

		// start frida-server again as manual
		pid_t pid;
    	int status;
		if(withArgs) {
			const char* args[] = {"/usr/sbin/frida-server", [op1 UTF8String], [op2 UTF8String], NULL};
    		posix_spawn(&pid, "/usr/sbin/frida-server", NULL, NULL, (char* const*)args, NULL);
		}
		else {
			const char* args[] = {"/usr/sbin/frida-server", NULL};
    		posix_spawn(&pid, "/usr/sbin/frida-server", NULL, NULL, (char* const*)args, NULL);
		}
		waitpid(pid, &status, WEXITED);
		printf("frida-server is now on.\n\n");
	}
}

void installFrida(NSString *filePath){
	NSString *input = [NSString stringWithFormat:@"dpkg -i %@ 2>/dev/null", filePath];
	printf("%s\n", [shellCommand(input) UTF8String]);

	checkWeirdFridaProcess(NO, NULL, NULL);
}

// Download frida-server
void downloadFrida(NSString *fridaVersion){
	NSString *downloadURL = [NSString stringWithFormat:@"https://github.com/frida/frida/releases/download/%@/frida_%@_iphoneos-arm.deb", fridaVersion, fridaVersion];
	NSURL *url = [NSURL URLWithString:downloadURL];

	// Create request.
    NSURLRequest *request = [NSURLRequest requestWithURL:url];

	// Create shared NSURLSession object.
    NSURLSession *sharedSession = [NSURLSession sharedSession];
	
	// check if frida-server file is already exists at current directory.
	NSString *currDir = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *filePath = [NSString stringWithFormat:@"%@/frida-server-%@",currDir,fridaVersion];
	BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
	if(fileExists){
		printf("frida-server file already exists. Installing...\n");
		installFrida(filePath);
		exit(0);
	}

	// Create download task
    NSURLSessionDownloadTask *downloadTask = [sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
    	if (error == nil) {
			NSError *fileError;
        	[[NSFileManager defaultManager] copyItemAtPath:location.path toPath:filePath error:&fileError];
        	if (fileError == nil) {
        	    printf("file download and save success at %s\n", [filePath UTF8String]);
				printf("Installing frida...\n");
				installFrida(filePath);
				exit(0);
        	} else {
        	    NSLog(@"file save error: %@",fileError);
				exit(-1);
        	}
    	} else {
    	        NSLog(@"download error:%@",error);
				exit(-2);
    	}
    }];

    // Start download task.
    [downloadTask resume];
	
	dispatch_main();
}

// check if frida-server is installed
static BOOL isFridaInstalled() {
	BOOL installed = NO;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:fridaplistPath]) {
		installed = YES;
	}
	return installed;	
}

static BOOL isRepoInstalled() {
	BOOL repoInstalled = NO;
	int val = (int)[shellCommand(@"grep -rli 'build.frida.re' /etc/apt/sources.list.d/* | wc -l") integerValue];
	if(val != 0){
		repoInstalled = YES;
	}
	return repoInstalled;
}

void showHelp(){
	printf("\nUsage: fricon <command> [options]\n\n");
	printf("Commnad:\n");
	printf("\tstart: Launch Frida Server\n");
	printf("\tstop: Kill Frida Server\n");
	printf("\tdownload: Download latest frida-server\n");
	printf("\tstat: Show frida-server status\n");
	printf("\tversion: Show frida-server version\n");
	printf("\tremove: Remove frida\n");
	printf("\thelp: Show help\n");
	printf("Options:\n");
	printf("\t-l, --listen <ADDRESS:PORT>: Listen on ADDRESS(only with start command) (ex. fricon start --listen 0.0.0.0:27043)\n");
	printf("\t-v, --version <version>: Download Specific version of frida-server(only with download command) (ex. fricon download --version 15.0.8)\n\n");
}

void showStat(NSString *processName){
	if(isProcessRunning(processName)){
		NSString *input = [NSString stringWithFormat:@"ps -ef | grep %@ | grep -v grep", processName];
		printf("%s\n", [shellCommand(input) UTF8String]);
	} else {
		printf("frida-server is not running.\n\n");
	}
}

void writeFridaPlist(NSString *op1, NSString *op2){
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:fridaplistPath];

	[[dict objectForKey:@"ProgramArguments"] addObject:op1];
	[[dict objectForKey:@"ProgramArguments"] addObject:op2];
	
	[dict writeToFile:fridaplistPath atomically:YES];
}

void recoverFridaPlist(){
	NSString *origProgramArguments = @"/usr/sbin/frida-server";
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:fridaplistPath];
	[dict setObject:[[NSMutableArray alloc] initWithObjects:origProgramArguments,nil] forKey:@"ProgramArguments"];
	[dict writeToFile:fridaplistPath atomically:YES];
}

void fridaStart(BOOL withArgs, NSString* op1, NSString* op2){
	if(!isFridaInstalled()) {
		printf("frida-server is not installed yet.\n\n");
		return;
	}

	if(isProcessRunning(@"frida-server")){
		printf("frida-server is already running. restarting...\n\n");
		fridaStop();
		printf("frida-server is now on.\n\n%s", [shellCommand(@"launchctl load /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null") UTF8String]);

		checkWeirdFridaProcess(withArgs, op1, op2);
	}
	else {
		printf("frida-server is on.\n\n%s", [shellCommand(@"launchctl load /Library/LaunchDaemons/re.frida.server.plist 2>/dev/null") UTF8String]);

		checkWeirdFridaProcess(withArgs, op1, op2);
	}
}

void fridaStartWithArgs(NSString *op1, NSString *op2){
	writeFridaPlist(op1, op2);
	fridaStart(YES, op1, op2);
}

int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool {
		// Process parameters
		NSArray *arguments =[[NSProcessInfo processInfo] arguments];

		if([arguments count] == 1){
			showHelp();
			return 0;
		}
		else if([arguments count] >= 2 && [arguments count] <= 4){
			NSString *command = [arguments objectAtIndex:1];
			if([command isEqualToString:@"start"]){
				if([arguments count] == 2){
					recoverFridaPlist();
					fridaStart(NO, NULL, NULL);
					return 0;
				}
				else if([arguments count] == 3){
					printf("\nUsage1: fricon <command> [options]. see fricon help\n\n");	
					return -1;
				} 
				else if([arguments count] == 4){
					NSString *op1 = [arguments objectAtIndex:2];
					if(![op1 isEqualToString:@"-l"] && ![op1 isEqualToString:@"--listen"]){
						printf("\nUsage2: fricon <command> [options]. see fricon help\n\n");	
						return -1;
					} else {
						NSString *op2 = [arguments objectAtIndex:3];
						recoverFridaPlist();
						fridaStartWithArgs(op1, op2);
						return 0;
					}
				}
			} else if([command isEqualToString:@"download"]){
				if(!isRepoInstalled()){
					// printf("frida repo is not addded. add \"https://build.frida.re\" in cydia or sileo sources.\n\n");
					// add frida repo /etc/apt/sources.list.d/sileo.sources
					printf("%s\n", [shellcommand(@"echo -e 'Types: deb\nURIs: https://build.frida.re\nSuites: ./\nComponents: \n' >> /etc/apt/sources.list.d/sileo.sources")]);
				}	

				if([arguments count] == 2){					
					int val = 0;
					while(!val){
						printf("%s\n", [shellCommand(@"apt-get clean") UTF8String]);
						printf("%s\n", [shellCommand(@"apt-get download re.frida.server --allow-unauthenticated -o APT::Sandbox::User=root") UTF8String]);
						val = (int)[shellCommand(@"ls | grep re.frida.server | wc -l") integerValue];
						sleep(1);
					}
					installFrida(@"re.frida.server*");
					return 0;
				} else if([arguments count] == 3){
					printf("\nUsage1: fricon <command> [options]. see fricon help\n\n");	
					return -1;
				} else if([arguments count] == 4) {
					NSString *op1 = [arguments objectAtIndex:2];
					if(![op1 isEqualToString:@"-v"] && ![op1 isEqualToString:@"--version"]){
						printf("\nUsage2: fricon <command> [options]. see fricon help\n\n");	
						return -1;
					} else {
						NSString *op2 = [arguments objectAtIndex:3];
						downloadFrida(op2);
						return 0;
					}
				}
			} else if([command isEqualToString:@"stop"] && [arguments count] == 2){
				if(!isFridaInstalled()) {
					printf("frida-server is not installed yet.\n\n");
					return -1;;
				}
				fridaStop();
				return 0;
			} else if([command isEqualToString:@"stat"] && [arguments count] == 2){
				if(!isFridaInstalled()) {
					printf("frida-server is not installed yet.\n\n");
					return -1;;
				}
				showStat(@"frida-server");
				return 0;
			} else if([command isEqualToString:@"version"] && [arguments count] == 2){
				if(!isFridaInstalled()) {
					printf("frida-server is not installed yet.\n\n");
					return -1;;
				}
				printf("frida-server version: %s\n", [shellCommand(@"frida-server --version") UTF8String]);
				return 0;
			} else if([command isEqualToString:@"remove"] && [arguments count] == 2){
				if(!isFridaInstalled()) {
					printf("frida-server is not installed yet.\n\n");
					return -1;;
				}
				printf("%s\n", [shellCommand(@"dpkg --purge re.frida.server") UTF8String]);
				printf("frida-server is removed\n\n");
				return 0;
			} else if([command isEqualToString:@"help"] && [arguments count] == 2){
				showHelp();
				return 0;
			} else {
				printf("\nUsage3: fricon <command> [options]. see fricon help\n\n");
				return -1;
			}
		}
		else {
			printf("\nUsage4: fricon <command> [options]. see fricon help\n\n");
			return -1;
		}
  	}
	return 0;
}
