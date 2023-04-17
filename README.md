# Take Home Test - Order Book on Sui

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
