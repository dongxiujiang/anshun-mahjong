# 麻将动画流程图

## 摸牌动画流程

```mermaid
sequenceDiagram
    participant R as RoundState
    participant C as AnimationController
    participant L as AnimationLayer
    participant P as PlayerTileAreas
    
    R->>C: emit draw event
    C->>C: _held_draw_seats[seat]++
    Note over C: 隐藏摸牌位持久节点
    C->>L: play(event)
    L->>L: 创建临时牌节点
    L->>L: 从牌墙飞到摸牌位
    Note over L: 抛物线 + 落桌回弹
    L->>C: _on_visual_animation_finished()
    C->>C: _held_draw_seats[seat]--
    alt remaining_holds == 0
        C->>P: draw_tile.visible = true
        C->>P: draw_tile.modulate.a = 1.0
        Note over P: 持久节点无缝接管
    end
```

## 手牌出牌三段动画流程

```mermaid
sequenceDiagram
    participant U as User
    participant C as AnimationController
    participant L as AnimationLayer
    participant H as hand_box
    participant D as draw_box
    
    U->>C: 点击手牌
    C->>C: _hand_snapshot()
    Note over C: 保存旧手牌位置
    C->>C: _held_refresh_seats[seat]++
    Note over C: 暂停手牌刷新
    C->>L: play(discard event)
    
    rect rgb(255, 240, 220)
    Note over L: 第 1 段（0-0.28s）
    L->>L: 被打出的牌飞向河牌
    C->>H: source_node.modulate.a = 0
    Note over C: 隐藏被打出的牌
    end
    
    rect rgb(220, 240, 255)
    Note over L: 第 2 段（0.28-0.56s）
    loop 每张剩余手牌
        L->>H: tile.position插值
        Note over H: 水平移动填补空位
    end
    end
    
    rect rgb(240, 255, 220)
    Note over L: 第 3 段（0.56-0.84s）
    L->>D: source_node.visible = false
    Note over D: 立即隐藏摸牌位源节点
    L->>L: 创建临时插入节点
    L->>H: 淡入 + 插入到排序位置
    Note over H: 抛物线插入
    end
    
    L->>C: _on_visual_animation_finished()
    C->>C: _commit_hand_discard_visual()
    Note over C: 物理节点提交到最终位置
    C->>C: _held_refresh_seats[seat]--
    alt remaining_holds == 0
        C->>H: _refresh()
        Note over H: 重建手牌，更新元数据
    end
```

## 遮罩控制逻辑

```mermaid
flowchart TD
    A[refresh_masks] --> B{动画类型}
    B -->|draw| C[遮罩目标位置牌]
    B -->|discard| D{从哪里打出}
    D -->|从手牌| E[只遮罩被打出的牌]
    D -->|从摸牌位| F[遮罩摸牌位的牌]
    B -->|meld| G[遮罩目标位置牌]
    B -->|meld_reveal| H[遮罩目标位置牌]
    
    E --> I[其他手牌保持可见]
    I --> J[玩家可见手牌移动]
    
    style E fill:#90EE90
    style I fill:#90EE90
    style J fill:#90EE90
```

## 坐标系统优化

```mermaid
graph LR
    A[原方案] -->|global_position插值| B[全局坐标系]
    B --> C[父节点旋转]
    C --> D[路径偏移❌]
    
    E[优化方案] -->|position插值| F[局部坐标系]
    F --> G[父节点旋转]
    G --> H[路径正确✓]
    
    style D fill:#FFB6C1
    style H fill:#90EE90
```

## 关键时序对比

### 优化前

```
出牌动画 (0.28s)
                  ↓
            手牌刷新（瞬间，从错误位置）
                  ↓
            所有牌闪烁❌
```

### 优化后

```
出牌动画 (0.28s)
                  ↓
        手牌移动填补空位 (0.28s)
                  ↓
        摸牌插入排序位置 (0.28s)
                  ↓
            提交物理节点✓
```

---

生成时间：2026-10-17  
工具：Codex AI
