# hacktributor

Add your [hacker news](https://news.ycombinator.com) comments to your
GitHub contribution graph! See
[milesforks/hacktributor](https://github.com/milesforks/hacktributor)
for an example.

## Installation

1. Fork this repository

2. Clone your fork: `git clone git@github.com:USERNAME/hacktributor.git`

## Running

Enter your hacktributor fork:

``` bash
cd /path/where/you/cloned/hacktributor
```

### Run with bash

To see usage:

``` bash
./feel_good_about_myself.sh
```

To run:

``` bash
./feel_good_about_myself.sh YOUR_HN_USERNAME [numDownloadWorkers=10]
```

If you've got a lot of comments (look at you!), you can increase parallel
downloads with the numDownloadWorkers setting.

### Run with bash... in Docker!

``` bash
./feel_better_about_myself.sh YOUR_HN_USERNAME [numDownloadWorkers=10]
```

Then, **push your changes** and wait for GitHub to update your contribution
graph.

Congratulations, you're awesome.

p.s. It doesn't even have to be your own username!
