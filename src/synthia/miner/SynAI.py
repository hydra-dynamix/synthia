from .template_miner import BaseMiner, miner_map

class Miner_0(BaseMiner):
    def __init__(self) -> None:
        super().__init__()

# Add the miner to the miner map
miner_map["Miner_0"] = Miner_0
