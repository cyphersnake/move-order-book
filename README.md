# Take Home Test - Order Book on Sui


## Solution
The task really wasn't that difficult! The language is simple enough and when I stopped reading the documentation and started reading the source code, I got the hang of it quickly enough.

### Run Tests
```bash
sui move test
```

### Architecture
A simple orderbook based on a priority queue is made. A modified `sui::priority_queue` was used, but this entailed a couple of unpleasant compromises (balance not in `Offer`, but in `Pair`). 

## FIXME
Unfortunately, my time under the task is over. Here's what I would have done had there been more of it:

- [ ] Write a better data-container for the priority queue so that the balance can be stored inside. I have seen different containers in other Move projects, so in theory it is not difficult to reuse or replicate them.
- [ ] Optimise in terms of resources spent. I am not yet familiar with this ecosystem, but it is obvious to the naked eye that my solution could be optimised by making the code a little less abstract.
- [ ] Calculate `coverage` & `prove`. There hasn't been enough time to figure out how to set up these commands. Both didn't work out of the box and would have been useful!
- [ ] Write functional tests through the client rather than through the built-in framework.
- [ ] Improve Dockerfile. I was developing on the native system, but wanted to use Dockerfile in CI. Ran into a problem that the image just hangs on cloning SUI if you copy the binary to an empty ubuntu. Didn't bother figuring it out, just pushed it in with the Rust container for now.

## Goal

Create an onchain order book for swapping tokens on Sui.

Minimal functionality: A user should be able to submit a bid order, which is matched with existing ask orders in the order book for one pair of tokens.

## Setup

Sui can either be installed locally or the docker file in the repo can be used.

To work with the provided container:

- Install docker desktop
- Install the VS code extension "Dev containers"
- In VS code, select the "Remote explorer" in the left navigation bar and click on open folder. Building the container for the first time might take 30min+ depending on your machine.
- Install the move-analyzer extension inside the container.
- Open a new terminal in VS code and run `sui move test`

## Resources

First application: https://docs.sui.io/build/move/write-package \
Move book: https://move-book.com/
